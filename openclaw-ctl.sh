#!/bin/zsh
# OpenClaw gateway control on macOS — the service layer behind OpenClaw.app.
#
# On macOS the gateway runs as a LaunchAgent, so starting it is SILENT: launchd
# spawns it in the background with no terminal window and no Dock icon. That is
# the main difference from the Windows launcher, which had to hide a console.
#
# Usage: openclaw-ctl.sh start|stop|restart|status|pid|open|url
export PATH="$HOME/.local/node/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

HOME_DIR="$HOME"
PORT=18789
CONFIG="$HOME/.openclaw/openclaw.json"
LOGDIR="$HOME/Library/Logs/openclaw"
LOG="$LOGDIR/gateway.log"

mkdir -p "$LOGDIR" 2>/dev/null

# The listening pid is the source of truth: `launchctl list` can show a job that
# is loaded but crash-looping, and a stale port owner outlives an unloaded job.
oc_pid() {
  /usr/sbin/lsof -nP -iTCP:$PORT -sTCP:LISTEN -t 2>/dev/null | head -1
}

wait_up() {
  for i in {1..60}; do
    sleep 0.5
    [ -n "$(oc_pid)" ] && return 0
  done
  return 1
}

wait_down() {
  for i in {1..30}; do
    sleep 0.5
    [ -z "$(oc_pid)" ] && return 0
  done
  return 1
}

# The Control UI needs the gateway token; `openclaw dashboard` builds exactly
# this URL (scheme http://127.0.0.1:PORT/#token=...). Read it ourselves so the
# caller doesn't pay for a node cold start.
oc_token() {
  /usr/bin/python3 -c "
import json,sys
try:
    d=json.load(open('$CONFIG'))
    print(d.get('gateway',{}).get('auth',{}).get('token','') or '')
except Exception:
    print('')
" 2>/dev/null
}

oc_url() {
  T=$(oc_token)
  if [ -n "$T" ]; then
    echo "http://127.0.0.1:$PORT/#token=$T"
  else
    echo "http://127.0.0.1:$PORT/"
  fi
}

case "$1" in
  start)
    P=$(oc_pid)
    if [ -n "$P" ]; then
      echo "already running (pid $P)"
      exit 0
    fi
    # Preferred path: launchd keeps it alive and restarts it if it dies.
    openclaw gateway start >/dev/null 2>&1
    if wait_up; then
      echo "started (pid $(oc_pid)) -> http://127.0.0.1:$PORT"
      exit 0
    fi
    # Fallback: launchd unavailable (e.g. job couldn't be bootstrapped) — run the
    # gateway detached so it still survives this shell and stays windowless.
    nohup openclaw gateway run --port $PORT >> "$LOGDIR/menubar-gateway.log" 2>&1 &
    if wait_up; then
      echo "started detached (pid $(oc_pid)) -> http://127.0.0.1:$PORT"
      exit 0
    fi
    echo "FAILED to start; see $LOG"
    tail -20 "$LOG" 2>/dev/null
    exit 1
    ;;
  stop)
    P=$(oc_pid)
    # Unload the LaunchAgent even when nothing is listening: a loaded-but-dead job
    # would otherwise respawn the gateway behind the user's back.
    openclaw gateway stop >/dev/null 2>&1
    if [ -z "$P" ]; then
      echo "stopped (was not running)"
      exit 0
    fi
    if wait_down; then
      echo "stopped"
      exit 0
    fi
    # A gateway started outside launchd (detached fallback) isn't ours to unload.
    kill "$P" 2>/dev/null
    if wait_down; then echo "stopped"; exit 0; fi
    kill -9 "$P" 2>/dev/null
    sleep 1
    [ -z "$(oc_pid)" ] && echo "force-stopped" || { echo "FAILED to stop (pid $P)"; exit 1; }
    ;;
  restart)
    "$0" stop >/dev/null
    sleep 1
    "$0" start
    ;;
  status)
    P=$(oc_pid)
    if [ -n "$P" ]; then echo "running:$P"; else echo "stopped"; fi
    ;;
  pid)
    oc_pid
    ;;
  url)
    oc_url
    ;;
  open)
    # One-click entry point: make sure it is up, then land on the Control UI.
    if [ -z "$(oc_pid)" ]; then "$0" start >/dev/null; fi
    URL=$(oc_url)
    open -a "Microsoft Edge" "$URL" 2>/dev/null || open "$URL"
    echo "opened $URL"
    ;;
  log)
    tail -${2:-30} "$LOG"
    ;;
  *)
    echo "usage: openclaw-ctl.sh start|stop|restart|status|pid|url|open|log [n]"
    exit 2
    ;;
esac
