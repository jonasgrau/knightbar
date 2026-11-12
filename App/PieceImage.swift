import ChessCore
import SwiftUI

extension Piece {
    /// Name of the image in the asset catalog, e.g. "Pieces/wN".
    var assetName: String {
        "Pieces/\(color == .white ? "w" : "b")\(kind.letter.uppercased())"
    }

    var localizedName: String {
        let color = color == .white ? "White" : "Black"
        let kind = switch kind {
        case .pawn: "pawn"
        case .knight: "knight"
        case .bishop: "bishop"
        case .rook: "rook"
        case .queen: "queen"
        case .king: "king"
        }
        return "\(color) \(kind)"
    }
}

struct PieceImage: View {
    let piece: Piece

    var body: some View {
        Image(piece.assetName)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .accessibilityLabel(piece.localizedName)
    }
}
