#!/bin/sh
# Downloads the official Stockfish release for macOS, verifies its checksum and
# places the engine binary in Vendor/stockfish/. The app's build copies it from there.
#
# It also extracts the engine's neural network into a separate file next to the binary.
# The Intel slice of the universal binary has no network of its own: it reads the one
# embedded in the arm64 slice at a fixed file offset. Signing the binary moves the slices,
# so the Intel slice would read the wrong bytes. With the network as a file next to it,
# Stockfish loads that instead, and the binary can be signed and notarized.
#
# To move to a newer release, change VERSION and SHA256 (listed next to the asset on
# https://github.com/official-stockfish/Stockfish/releases), and the NET_* values:
# NET_NAME is printed by "go" ("NNUE evaluation using …"), NET_SHA256 is the checksum of
# https://tests.stockfishchess.org/api/nn/<NET_NAME>, and NET_OFFSET/NET_SIZE are where
# those exact bytes start in the universal binary and how long they are.
set -eu

VERSION="sf_19"
ASSET="stockfish-macos-universal.tar.gz"
SHA256="a1f0e3bcc5a6927a11fe6fc8e54a779754645f3c2bae2cf13420fd1957adaa77"
URL="https://github.com/official-stockfish/Stockfish/releases/download/$VERSION/$ASSET"

NET_NAME="nn-1a298aa575a0.nnue"
NET_SHA256="1a298aa575a085434d29027978dc36867fe9c5bcea9376654b7a8eba1e52dfc2"
NET_OFFSET=5947904
NET_SIZE=98511183

root="$(cd "$(dirname "$0")/.." && pwd)"
dest="$root/Vendor/stockfish"
stamp="$dest/.version"

if [ -x "$dest/stockfish" ] && [ -f "$dest/$NET_NAME" ] \
    && [ "$(cat "$stamp" 2>/dev/null)" = "$VERSION $SHA256 $NET_SHA256" ]; then
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

tail -c "+$((NET_OFFSET + 1))" "$work/stockfish/stockfish-macos-universal" | head -c "$NET_SIZE" > "$work/$NET_NAME"
actual="$(shasum -a 256 "$work/$NET_NAME" | cut -d ' ' -f 1)"
if [ "$actual" != "$NET_SHA256" ]; then
    echo "error: the network extracted from the binary does not match $NET_NAME" >&2
    echo "  expected $NET_SHA256" >&2
    echo "  actual   $actual" >&2
    echo "  Check NET_OFFSET and NET_SIZE for this Stockfish release." >&2
    exit 1
fi

rm -rf "$dest"
mkdir -p "$dest"
mv "$work/stockfish/stockfish-macos-universal" "$dest/stockfish"
mv "$work/$NET_NAME" "$dest/"
mv "$work/stockfish/Copying.txt" "$work/stockfish/AUTHORS" "$dest/"
chmod +x "$dest/stockfish"
echo "$VERSION $SHA256 $NET_SHA256" > "$stamp"

echo "Stockfish $VERSION and its network $NET_NAME installed in $dest"
