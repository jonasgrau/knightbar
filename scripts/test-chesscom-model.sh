#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/knightbar-chesscom-tests.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export MACOSX_DEPLOYMENT_TARGET=14.0

swiftc -swift-version 6 -parse-as-library -emit-library -emit-module \
  -module-name ChessCore ChessCore/Sources/ChessCore/*.swift \
  -emit-module-path "$build_dir/ChessCore.swiftmodule" \
  -o "$build_dir/libChessCore.dylib"
swiftc -swift-version 6 -parse-as-library \
  -I "$build_dir" -L "$build_dir" -lChessCore \
  -Xlinker -rpath -Xlinker "$build_dir" \
  App/AppInfo.swift App/ChessComModel.swift App/LichessServices.swift \
  tests/ControlledHTTPTransport.swift tests/ChessComModelRegression.swift \
  -o "$build_dir/chesscom-model-tests"
"$build_dir/chesscom-model-tests"
