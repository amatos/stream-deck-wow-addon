#!/bin/sh
# Builds "WoW Bars Helper.app" into helper/build.
# SIGN_IDENTITY selects a code-signing identity; the default "-" is ad-hoc, which
# makes macOS ask for Screen Recording / Accessibility again after each rebuild.
set -eu

cd "$(dirname "$0")/.."
swift build -c release --product WoWBarsHelper

APP="build/WoW Bars Helper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/WoWBarsHelper" "$APP/Contents/MacOS/WoWBarsHelper"
# Regenerate with: swift tools/app-icon.swift <dir>/AppIcon.iconset && iconutil -c icns <dir>/AppIcon.iconset -o helper/Resources/AppIcon.icns
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>cc.matos.streamdeck.wowbars.helper</string>
    <key>CFBundleName</key>
    <string>WoW Bars Helper</string>
    <key>CFBundleDisplayName</key>
    <string>WoW Bars Helper</string>
    <key>CFBundleExecutable</key>
    <string>WoWBarsHelper</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- Starts without a Dock icon; the app turns it on when "Show in: Dock" is chosen. -->
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign "${SIGN_IDENTITY:--}" --identifier cc.matos.streamdeck.wowbars.helper "$APP"

# The bundle is recreated on every build, so refresh Launch Services and Finder's cached icon.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP"
touch "$APP"
echo "Built $APP"
