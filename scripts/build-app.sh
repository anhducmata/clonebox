#!/bin/sh
# Builds build/CloneBox.app with SwiftPM (no Xcode needed). Pass --install to copy it to ~/Applications.
set -eu
cd "$(dirname "$0")/.."

swift build -c release
BIN=".build/release"
APP="build/CloneBox.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/CloneBox" "$APP/Contents/MacOS/CloneBox"
cp "$BIN/clonebox-launcher" "$APP/Contents/Resources/clonebox-launcher"
"$BIN/CloneBox" make-app-icon "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.clonebox.manager</string>
    <key>CFBundleName</key><string>CloneBox</string>
    <key>CFBundleDisplayName</key><string>CloneBox</string>
    <key>CFBundleExecutable</key><string>CloneBox</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP/Contents/Resources/clonebox-launcher"
codesign --force --sign - "$APP"
echo "built $APP"

if [ "${1:-}" = "--install" ]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/CloneBox.app"
    cp -R "$APP" "$HOME/Applications/CloneBox.app"
    echo "installed $HOME/Applications/CloneBox.app"
fi
