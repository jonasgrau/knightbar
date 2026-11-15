#!/bin/sh
# Xcode build phase "Copy Stockfish": copies the engine, its network and its licence files
# into the app's Resources/Stockfish/ and signs the engine.
#
# The network is shipped as a separate file next to the engine, and Stockfish loads it from
# there. That is what makes signing safe: the Intel slice of the universal binary would
# otherwise read the network from the arm64 slice at a fixed file offset, and signing moves
# the slices (see scripts/fetch-stockfish.sh).
#
# The engine is signed with the app's identity and the hardened runtime, as notarization
# requires for every executable in the bundle. Xcode then seals it into the app signature.
set -eu

src="$SRCROOT/Vendor/stockfish"
net="$(find "$src" -maxdepth 1 -name 'nn-*.nnue' | head -1)"
if [ ! -x "$src/stockfish" ] || [ -z "$net" ]; then
    echo "error: Stockfish or its network is missing. Run scripts/fetch-stockfish.sh, then build again."
    exit 1
fi

dst="$BUILT_PRODUCTS_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/Stockfish"
mkdir -p "$dst"
# Remove networks of an older Stockfish version.
find "$dst" -maxdepth 1 -name 'nn-*.nnue' ! -name "$(basename "$net")" -delete

cp -f "$src/stockfish" "$dst/stockfish"
cp -f "$net" "$src/Copying.txt" "$src/AUTHORS" "$dst/"

identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [ "$identity" = "-" ]; then
    # Ad-hoc signature for local builds; a secure timestamp needs a real identity.
    codesign --force --sign - --options runtime "$dst/stockfish"
else
    codesign --force --sign "$identity" --options runtime --timestamp "$dst/stockfish"
fi
