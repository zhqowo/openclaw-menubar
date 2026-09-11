#!/bin/zsh
# Build OpenClaw.app (macOS menu-bar launcher for the OpenClaw gateway) and install
# it to the Desktop. Self-contained: everything is read from this script's own
# directory, so it can be re-run any time:
#
#     zsh build.sh
#
# To build WITHOUT touching an installed copy (e.g. to produce a distributable zip):
#
#     OPENCLAW_APP_OUT=/tmp/claw-staging/OpenClaw.app zsh build.sh
#
# In that mode the script never replaces ~/Desktop/OpenClaw.app, never kills a
# running ClawLauncher, never nudges Finder, and never launches the result.
#
# Same three macOS gotchas 大肥鱼.app's build works around:
#  1. xcrun defaults to the MacOSX27 SDK, which the installed Swift compiler cannot
#     read -> pass an explicit -sdk.
#  2. `SetFile -a C` marks a bundle as "has a custom icon"; without it Finder draws
#     a generic icon instead of CFBundleIconFile.
#  3. `cp -R src dst` NESTS when dst exists -> remove the destination first.
export PATH="$HOME/.local/node/bin:/usr/bin:/bin:/usr/sbin:/sbin"
set -e

HERE="$(cd "$(dirname "$0")" && pwd)"
BUILD="$HOME/openclaw-menubar-build"
DEFAULT_APP="$HOME/Desktop/OpenClaw.app"
APP="${OPENCLAW_APP_OUT:-$DEFAULT_APP}"
STAGING=0
[ "$APP" != "$DEFAULT_APP" ] && STAGING=1
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

rm -rf "$BUILD"; mkdir -p "$BUILD/assets"

echo "=== 0. source files ==="
for f in main.swift icon_compose.swift openclaw-ctl.sh assets/lobster1024.png; do
  [ -f "$HERE/$f" ] || { echo "missing $HERE/$f"; exit 1; }
done
cp "$HERE/main.swift" "$BUILD/main.swift"
cp "$HERE/icon_compose.swift" "$BUILD/icon_compose.swift"
cp "$HERE/openclaw-ctl.sh" "$BUILD/openclaw-ctl.sh"
cp "$HERE/assets/lobster1024.png" "$BUILD/assets/lobster1024.png"

SDK=$(/bin/ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | /usr/bin/head -1)
[ -z "$SDK" ] && SDK=$(/bin/ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk 2>/dev/null | /usr/bin/grep -v 27 | /usr/bin/head -1)
echo "  SDK: $SDK"

echo "=== 1. menu-bar icon (18pt @1x/@2x, transparent bg) ==="
/usr/bin/sips -z 18 18 "$BUILD/assets/lobster1024.png" --out "$BUILD/assets/claw.png" >/dev/null
/usr/bin/sips -z 36 36 "$BUILD/assets/lobster1024.png" --out "$BUILD/assets/claw@2x.png" >/dev/null

echo "=== 2. compose the app icon (light card + lobster) ==="
/usr/bin/swiftc -sdk "$SDK" -swift-version 5 -o "$BUILD/icon_compose" "$BUILD/icon_compose.swift" -framework AppKit
"$BUILD/icon_compose" "$BUILD/assets/lobster1024.png" "$BUILD/assets/icon_base.png" 1024 0.84

echo "=== 3. icns from the composed base ==="
ICONSET="$BUILD/assets/claw.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  /usr/bin/sips -z $s $s "$BUILD/assets/icon_base.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1
  /usr/bin/sips -z $((s*2)) $((s*2)) "$BUILD/assets/icon_base.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null 2>&1
done
/usr/bin/iconutil -c icns "$ICONSET" -o "$BUILD/assets/AppIcon.icns"

echo "=== 4. compile the app ==="
cd "$BUILD"
/usr/bin/swiftc -sdk "$SDK" -O -swift-version 5 -o "$BUILD/ClawLauncher" "$BUILD/main.swift" -framework Cocoa

echo "=== 5. assemble bundle ==="
BUNDLE="$BUILD/OpenClaw.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BUILD/ClawLauncher" "$BUNDLE/Contents/MacOS/ClawLauncher"
cp "$BUILD/assets/claw.png"    "$BUNDLE/Contents/Resources/claw.png"
cp "$BUILD/assets/claw@2x.png" "$BUNDLE/Contents/Resources/claw@2x.png"
cp "$BUILD/assets/AppIcon.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
# Bundle the service layer so a downloaded copy works with no manual setup.
# main.swift's resolveCtlPath() finds it via Bundle.main.
cp "$BUILD/openclaw-ctl.sh" "$BUNDLE/Contents/Resources/openclaw-ctl.sh"
chmod +x "$BUNDLE/Contents/Resources/openclaw-ctl.sh"
printf 'APPL????' > "$BUNDLE/Contents/PkgInfo"
cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>OpenClaw</string>
    <key>CFBundleDisplayName</key><string>OpenClaw</string>
    <key>CFBundleExecutable</key><string>ClawLauncher</string>
    <key>CFBundleIdentifier</key><string>local.openclaw.menubar</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleSignature</key><string>????</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "=== 6. ad-hoc sign ==="
/usr/bin/codesign --force --sign - "$BUNDLE" 2>&1 | tail -1 || true

echo "=== 7. install ==="
if [ "$STAGING" = "1" ]; then
  rm -rf "$APP"
  mkdir -p "$(dirname "$APP")"
  cp -R "$BUNDLE" "$APP"
  echo "  staged at: $APP"
  echo "  (skipped: killing a running ClawLauncher, replacing the Desktop app,"
  echo "            Finder/icon-cache refresh, launching)"
  echo "DONE (staging build, Desktop app untouched)"
  exit 0
fi

pkill -f "ClawLauncher" 2>/dev/null || true
sleep 1
rm -rf "$APP"
cp -R "$BUNDLE" "$APP"

echo "=== 8. attributes + LaunchServices + Finder refresh ==="
/usr/bin/SetFile -a c "$APP" 2>/dev/null || true
/usr/bin/xattr -c "$APP" 2>/dev/null || true
"$LSREG" -f "$APP" 2>/dev/null || true
/usr/bin/touch "$APP"
/usr/bin/killall iconservicesagent 2>/dev/null || true
rm -rf "$HOME/Library/Caches/com.apple.iconservices" 2>/dev/null || true
/usr/bin/killall Finder 2>/dev/null || true
sleep 3

echo "=== 9. launch ==="
open "$APP"
sleep 3
pgrep -f ClawLauncher >/dev/null && echo "  ✅ running (pid $(pgrep -f ClawLauncher | head -1))" || echo "  ❌ not running"

echo "=== 10. verify ==="
echo "  kind : $(/usr/bin/mdls -name kMDItemKind "$APP" 2>/dev/null | cut -d= -f2)"
echo "  icon : $(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$APP/Contents/Info.plist").icns"
echo "DONE"
