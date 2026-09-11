#!/bin/zsh
# Regenerate the lobster art from the installed OpenClaw package.
#
# OpenClaw ships its mascot as a vector favicon inside the npm package; re-run this
# after `npm i -g openclaw` so the launcher's icon follows the official artwork
# instead of drifting from a stale copy. The derived files are committed in
# assets/, so this is only needed when OpenClaw itself is updated.
#
#     zsh ~/DeepSeekHarness/migration/openclaw-menubar/make_assets.sh
export PATH="$HOME/.local/node/bin:/usr/bin:/bin:/usr/sbin:/sbin"
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HOME/.local/node/lib/node_modules/openclaw/dist/control-ui/favicon.svg"
OUT="$HERE/assets"

[ -f "$SRC" ] || { echo "not found: $SRC (is openclaw installed globally?)"; exit 1; }

SDK=$(/bin/ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | /usr/bin/head -1)
[ -z "$SDK" ] && SDK=$(/bin/ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | /usr/bin/grep -v 27 | /usr/bin/head -1)
echo "SDK: $SDK"

mkdir -p "$OUT"
cp "$SRC" "$OUT/favicon.svg"
cp "$(dirname "$SRC")/apple-touch-icon.png" "$OUT/apple-touch-icon.png"

echo "=== rasterize favicon.svg -> lobster1024.png (transparent) ==="
/usr/bin/swiftc -sdk "$SDK" -O -o /tmp/oc_svg2png "$HERE/svg2png.swift" -framework AppKit
/tmp/oc_svg2png "$OUT/favicon.svg" "$OUT/lobster1024.png" 1024

echo "=== menu-bar sizes (18pt @1x/@2x) ==="
/usr/bin/sips -z 18 18 "$OUT/lobster1024.png" --out "$OUT/claw.png" >/dev/null
/usr/bin/sips -z 36 36 "$OUT/lobster1024.png" --out "$OUT/claw@2x.png" >/dev/null
/usr/bin/sips -g pixelWidth "$OUT/claw.png" "$OUT/claw@2x.png" | grep -E "pixelWidth|png$"

echo "DONE — assets refreshed from OpenClaw $(openclaw --version 2>/dev/null | head -1)"
