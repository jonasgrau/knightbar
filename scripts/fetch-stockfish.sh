#!/bin/sh
# Downloads the official Stockfish release for macOS, verifies its checksum and
# places the engine binary in Vendor/stockfish/. The app's build copies it from there.
#
# To move to a newer release, change VERSION and SHA256. The checksum is listed
# next to the asset on https://github.com/official-stockfish/Stockfish/releases.
set -eu

VERSION="sf_19"
ASSET="stockfish-macos-universal.tar.gz"
SHA256="a1f0e3bcc5a6927a11fe6fc8e54a779754645f3c2bae2cf13420fd1957adaa77"
URL="https://github.com/official-stockfish/Stockfish/releases/download/$VERSION/$ASSET"

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/Vendor/stockfish"
stamp="$dest/.version"

if [ -x "$dest/stockfish" ] && [ "$(cat "$stamp" 2>/dev/null)" = "$VERSION $SHA256" ]; then
    echo "Stockfish $VERSION is already in place."
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

echo "Downloading $URL"
curl --fail --location --silent --show-error --output "$work/$ASSET" "$URL"

actual="$(shasum -a 256 "$work/$ASSET" | cut -d ' ' -f 1)"
if [ "$actual" != "$SHA256" ]; then
    echo "error: checksum mismatch for $ASSET" >&2
    echo "  expected $SHA256" >&2
    echo "  actual   $actual" >&2
    exit 1
fi

tar -xzf "$work/$ASSET" -C "$work" \
    stockfish/stockfish-macos-universal stockfish/Copying.txt stockfish/AUTHORS

rm -rf "$dest"
mkdir -p "$dest"
mv "$work/stockfish/stockfish-macos-universal" "$dest/stockfish"
mv "$work/stockfish/Copying.txt" "$work/stockfish/AUTHORS" "$dest/"
chmod +x "$dest/stockfish"
echo "$VERSION $SHA256" > "$stamp"

echo "Stockfish $VERSION installed at $dest/stockfish"
