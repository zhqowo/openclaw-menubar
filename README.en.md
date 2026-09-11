# 🦞 OpenClaw Lobster · macOS menu bar

English | [中文](README.md)

An **on/off switch** for the [OpenClaw](https://github.com/openclaw/openclaw) gateway:
a lobster in the top-right corner — **left click** opens the Control UI, **right click**
starts/stops the gateway, and quitting stops the service with it.

![Platform](https://img.shields.io/badge/platform-macOS-black)
![Shape](https://img.shields.io/badge/shape-menu%20bar-red)
![Language](https://img.shields.io/badge/Swift-AppKit-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

> Sibling project on the same skeleton: **[🐳 Da Fei Yu](https://github.com/zhqowo/dsh-whale-tray)** —
> the tray / menu-bar launcher for DeepSeek Harness. The two icons can sit side by side in the menu bar.

## Download

Don't want to build it? Grab the packaged app (**unzip and run**):

| File | What |
|---|---|
| [`OpenClaw.app.zip`](https://github.com/zhqowo/openclaw-menubar/releases/latest) | macOS menu-bar lobster (ad-hoc signed) |

Because it is ad-hoc signed, Gatekeeper blocks the first launch: right-click → **Open**, or

```sh
xattr -d com.apple.quarantine OpenClaw.app
```

**No extra setup required** — the service-layer script `openclaw-ctl.sh` ships inside the app bundle.

## Usage

| Action | Behaviour |
|---|---|
| **Left click** | Opens the Control UI, starting the gateway first if needed. If a tab is already open it **raises that tab** instead of piling up new ones |
| **Right click** | Just two items: `Start gateway` / `Stop gateway` (whichever applies) + `Quit` |
| **Full-colour icon** | Gateway running |
| **Dimmed icon** | Gateway stopped |

No restart item, no status line, no top-up — the icon's brightness carries the whole state.

## Design notes

**Starting is silent on macOS.** The gateway runs under launchd as a LaunchAgent
(`~/Library/LaunchAgents/ai.openclaw.gateway.plist`): backgrounded, no terminal window,
no Dock icon. The Windows build has to work to hide a console; macOS doesn't.

**Quitting stops the gateway.** `applicationWillTerminate` calls `openclaw-ctl.sh stop`, so
the menu-bar icon can't disappear while the service keeps running in the background.

> If you'd rather **quit the icon but leave the gateway running** (say it hosts WeChat or cron
> jobs), delete the whole `applicationWillTerminate` function from `main.swift` and rebuild.

**Left click lands pre-authenticated.** The Control UI accepts `gateway.auth.token`, and the
official `openclaw dashboard` works by putting that token in the URL fragment. This app reads
the token straight out of `~/.openclaw/openclaw.json` and builds the same URL — so **rotating the
token needs no rebuild**.

## Layout

```
main.swift         # main program (Swift / Cocoa), including the openclaw-ctl.sh lookup
icon_compose.swift # composes the app icon (light card + lobster)
svg2png.swift      # SVG → transparent PNG (qlmanage pads white; unusable)
make_assets.sh     # re-export icon assets from the installed OpenClaw package
build.sh           # compile + package + install (OPENCLAW_APP_OUT for staging builds)
openclaw-ctl.sh    # service layer: start/stop/restart/status/pid/url/open/log
assets/
  favicon.svg         # official vector mascot (copied from the npm package)
  lobster1024.png     # 1024×1024 transparent lobster
  claw.png / claw@2x.png   # menu-bar 18pt @1x/@2x
  apple-touch-icon.png     # official 180px alternate
dist/              # packaged .app.zip
```

## Where the service-layer script goes

The app only shells out to `openclaw-ctl.sh`; it implements no gateway logic itself.
**Since v1.1 that script is bundled inside the app**, so a downloaded copy works out of the box
with nothing to place by hand.

If you want your own script — or one living elsewhere — these are searched in order and the
**first executable wins**:

| # | Location | Purpose |
|---|---|---|
| 1 | `$OPENCLAW_MENUBAR_CTL` | environment variable, one-off override |
| 2 | `ctlPath` in `~/.config/openclaw-menubar/config.json` | persistent override, no rebuild needed |
| 3 | **bundled in the app** — `Contents/Resources/openclaw-ctl.sh` | the default, works out of the box |
| 4 | `~/.local/bin/openclaw-ctl.sh` | your own install |
| 5 | `~/DeepSeekHarness/bin/openclaw-ctl.sh` | where older builds hardcoded it — kept for compatibility |

```jsonc
// ~/.config/openclaw-menubar/config.json
{
  "ctlPath": "~/bin/my-openclaw-ctl.sh"   // ~ is expanded
}
```

A custom script only needs to handle `status` / `start` / `stop` — those are the only three the
app calls. **When nothing is found the menu items don't fail silently**: the app tells you where
to put the script.

## Building

```sh
zsh build.sh          # compile and install to the Desktop
zsh make_assets.sh    # refresh icon assets after upgrading OpenClaw
```

Output: `~/Desktop/OpenClaw.app` (bundle id `local.openclaw.menubar`, ad-hoc signed)

To avoid clobbering an installed copy — e.g. to produce a distributable zip:

```sh
OPENCLAW_APP_OUT=/tmp/staging/OpenClaw.app zsh build.sh
```

In that mode the script does **not** replace the Desktop app, kill a running process, touch
Finder, or launch the result.

## Service-layer behaviour

- `start` — runs `openclaw gateway start` first (launchd-managed, restarts itself if it dies);
  when launchd isn't available it falls back to a detached `nohup openclaw gateway run`, equally windowless
- `stop` — **always unloads the LaunchAgent**, listening or not; otherwise a job that is "loaded
  but dead" quietly pulls the gateway back up. Only if unloading fails does it degrade to
  `kill` → `kill -9`
- The only evidence that counts as "running" is **a process listening on port 18789** (`lsof`),
  because `launchctl list` may show a job that is crash-looping

## 🖼️ Artwork credit

**Both the menu-bar icon and the app icon come from OpenClaw's official mascot — I didn't draw them.**

- **Original copyright: the OpenClaw project** — [openclaw/openclaw](https://github.com/openclaw/openclaw)
- **Source file**: `dist/control-ui/favicon.svg` inside the official OpenClaw npm package
  (locally `~/.local/node/lib/node_modules/openclaw/dist/control-ui/favicon.svg`).
  The vector original is kept in [`assets/favicon.svg`](assets/favicon.svg)
- **How it was obtained**: straight from the npm package, not from any third-party icon site

No artistic changes were made — only mechanical ones:

| File | How it was produced |
|---|---|
| `assets/lobster1024.png` | SVG → 1024×1024 PNG with a **transparent background** (`svg2png.swift`) |
| `assets/claw.png` / `claw@2x.png` | the above scaled to 18px / 36px menu-bar icons |
| `Contents/Resources/AppIcon.icns` | the above laid over a gradient card (`icon_compose.swift`), then converted to icns |

> If the OpenClaw maintainers would like the credit adjusted, or these assets replaced or removed,
> open an issue and it will be handled immediately.

### Two technical traps

`svg2png.swift` is a requirement, not fastidiousness: **`qlmanage -t` renders an SVG onto an opaque
white background**, which becomes a white blob in the menu bar. `NSImage` can read SVG directly and
re-rasterise at the target size, so scaling up to 1024 stays sharp.

The menu-bar icon carries both an 18px (@1x) and a 36px (@2x) rep:
`NSImage(contentsOfFile:)` does **not** auto-load the `@2x` sibling, so a single rep looks fuzzy on Retina.

Full third-party asset notice: [NOTICE](NOTICE).

## ⚠️ Does it need permissions?

**The app itself needs no TCC grant at all.** It does three things: probe a TCP port, run
`openclaw-ctl.sh`, and use AppleScript to switch tabs (that needs the **Automation** permission —
you'll get a prompt on the first left click, and declining merely falls back to opening a new tab).

So it **can be rebuilt freely** — unlike "Da Fei Yu", which is bound by the cdhash rule that
"a rebuild invalidates every grant" (under an ad-hoc signature macOS keys grants to the binary
hash, so rebuilding changes the hash; Da Fei Yu holds Screen Recording / Accessibility / Full Disk
Access, which is why its binary is frozen. See
[the TCC section in the Da Fei Yu repo](https://github.com/zhqowo/dsh-whale-tray/blob/main/macos/README.md)).

## Verified

- Start 5.9s / stop 4.3s; a repeated `start` is idempotent (reports `already running`)
- Both lobster states are correct: full colour while the gateway runs, dimmed within 3s of stopping
- The URL left click lands on carries the token, so the Control UI **opens straight into the chat
  view with no auth prompt**
- The icon is sharp on Retina (it uses the 36px @2x image, not an upscaled 18px one)
- The right-click menu really is just "Start gateway / Quit"; clicking Start brings the gateway up
  and it answers HTTP 200
- macOS rounds the desktop icon properly

## License

[MIT](LICENSE) © 2026 zhqowo — use it, change it, ship it commercially; just keep the copyright notice.
The bundled lobster artwork belongs to the OpenClaw project; see [NOTICE](NOTICE).
