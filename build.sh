#!/bin/zsh
# Builds MenuStats.app from source and (optionally) installs it to ~/Applications.
#   ./build.sh            build into ./build/MenuStats.app
#   ./build.sh install    build, copy to ~/Applications, and launch
set -euo pipefail
cd "$(dirname "$0")"

APP=build/MenuStats.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -target "$(uname -m)-apple-macos26.0" \
  -o "$APP/Contents/MacOS/MenuStats" Sources/*.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>MenuStats</string>
  <key>CFBundleIdentifier</key><string>local.menustats</string>
  <key>CFBundleName</key><string>MenuStats</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: required on Apple Silicon, no developer account needed.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x MenuStats 2>/dev/null || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/MenuStats.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/MenuStats.app
  echo "Installed to ~/Applications/MenuStats.app"
fi
