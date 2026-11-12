#!/bin/sh
# Packs an app bundle into a compressed disk image with the usual drag-to-Applications window.
#
# Usage: scripts/make-dmg.sh <path/to/Knightbar.app> <output.dmg>
set -eu

app="$1"
output="$2"
name="$(basename "$app" .app)"

work="$(mktemp -d)"
mountpoint="$work/mount"
trap 'hdiutil detach "$mountpoint" -quiet 2>/dev/null || true; rm -rf "$work"' EXIT

staging="$work/staging"
mkdir -p "$staging"
# ditto keeps the bundle's signature intact.
ditto "$app" "$staging/$name.app"
ln -s /Applications "$staging/Applications"

hdiutil create -quiet -volname "$name" -srcfolder "$staging" -fs HFS+ -format UDRW -ov "$work/rw.dmg"
mkdir -p "$mountpoint"
hdiutil attach -quiet -noautoopen -mountpoint "$mountpoint" "$work/rw.dmg"

# Arrange the window: the app on the left, the Applications folder on the right. The image is
# mounted visibly for this, because Finder cannot address a volume attached with -nobrowse.
# This needs Finder automation; without it the image still works, just unarranged.
osascript <<APPLESCRIPT || echo "note: could not arrange the Finder window, continuing without layout"
with timeout of 30 seconds
    tell application "Finder"
        set dmgFolder to (POSIX file "$mountpoint" as alias)
        open dmgFolder
        set theWindow to container window of dmgFolder
        set current view of theWindow to icon view
        set toolbar visible of theWindow to false
        set statusbar visible of theWindow to false
        set bounds of theWindow to {200, 120, 740, 540}
        set viewOptions to icon view options of theWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set position of item "$name.app" of dmgFolder to {140, 140}
        set position of item "Applications" of dmgFolder to {400, 140}
        update dmgFolder without registering applications
        delay 1
        close theWindow
    end tell
end timeout
APPLESCRIPT

# Drop the file system event log the mount created; it does not belong in the image.
rm -rf "$mountpoint/.fseventsd"
sync
hdiutil detach -quiet "$mountpoint"
rm -f "$output"
hdiutil convert -quiet "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$output"
echo "Created $output"
