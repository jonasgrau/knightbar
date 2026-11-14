#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/knightbar-replay-benchmark.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export MACOSX_DEPLOYMENT_TARGET=14.0

# Match the app's separately compiled Release library boundary. Fixture generation,
# JSON fixture setup, compilation and loading the library are outside timed regions.
swiftc -swift-version 6 -O -whole-module-optimization -parse-as-library \
  -emit-library -emit-module -module-name ChessCore \
  ChessCore/Sources/ChessCore/*.swift \
  -emit-module-path "$build_dir/ChessCore.swiftmodule" -o "$build_dir/libChessCore.dylib"
swiftc -swift-version 6 -O -whole-module-optimization -parse-as-library \
  -I "$build_dir" -L "$build_dir" -lChessCore \
  -Xlinker -rpath -Xlinker "$build_dir" \
  scripts/benchmark-replay.swift -o "$build_dir/benchmark-replay"
"$build_dir/benchmark-replay" "$@"
