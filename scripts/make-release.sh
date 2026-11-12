#!/bin/sh
# Builds Knightbar for Apple Silicon and Intel, checks the result and packs it as a .zip
# (for Homebrew) and a .dmg (for people) for a GitHub release. Both files and their SHA-256
# checksums end up in dist/.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

"$root/scripts/fetch-stockfish.sh"

build="$root/build"
rm -rf "$build"
xcodebuild -project Knightbar.xcodeproj -scheme Knightbar -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath "$build" ONLY_ACTIVE_ARCH=NO build -quiet

app="$build/Build/Products/Release/Knightbar.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"

echo "Checking $app"
codesign --verify --deep --strict "$app"
for binary in "$app/Contents/MacOS/Knightbar" "$app/Contents/Resources/Stockfish/stockfish"; do
    archs="$(lipo -archs "$binary")"
    case "$archs" in
        *x86_64*arm64* | *arm64*x86_64*) ;;
        *) echo "error: $binary contains only $archs" >&2; exit 1 ;;
    esac
done

dist="$root/dist"
mkdir -p "$dist"
archive="$dist/Knightbar-$version.zip"
rm -f "$archive"
# ditto keeps the bundle's signature and extended attributes intact.
ditto -c -k --keepParent "$app" "$archive"
(cd "$dist" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
echo "Created $archive"

image="$dist/Knightbar-$version.dmg"
"$root/scripts/make-dmg.sh" "$app" "$image"
(cd "$dist" && shasum -a 256 "$(basename "$image")" > "$(basename "$image").sha256")

cat "$archive.sha256" "$image.sha256"
