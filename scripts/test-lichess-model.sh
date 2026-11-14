#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/knightbar-lichess-tests.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
export MACOSX_DEPLOYMENT_TARGET=14.0

swiftc -swift-version 6 -parse-as-library -emit-library -emit-module \
  -module-name ChessCore ChessCore/Sources/ChessCore/*.swift \
  -emit-module-path "$build_dir/ChessCore.swiftmodule" \
  -o "$build_dir/libChessCore.dylib"
swiftc -swift-version 6 -parse-as-library \
  -I "$build_dir" -L "$build_dir" -lChessCore \
  -Xlinker -rpath -Xlinker "$build_dir" \
  App/BoardView.swift App/PieceImage.swift App/AppInfo.swift \
  App/LichessModel.swift App/LichessServices.swift App/ChessComModel.swift \
  ChessCore/Tests/ChessCoreTests/Fixtures/LichessFixtures.swift \
  tests/ControlledHTTPTransport.swift tests/LichessModelRegression.swift -o "$build_dir/lichess-model-tests"
"$build_dir/lichess-model-tests"
