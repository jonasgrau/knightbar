import ChessCore
import SwiftUI

/// Promotion piece chooser, laid over the board.
struct PromotionPicker: View {
    let color: PieceColor
    let onChoose: (PieceKind) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
                .accessibilityLabel("Cancel promotion")
                .accessibilityAddTraits(.isButton)

            HStack(spacing: 6) {
                ForEach(Move.promotionKinds, id: \.self) { kind in
                    let piece = Piece(color: color, kind: kind)
                    Button {
                        onChoose(kind)
                    } label: {
                        PieceImage(piece: piece)
                            .frame(width: 52, height: 52)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(piece.localizedName)
                }
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 8)
        }
        .onExitCommand(perform: onCancel)
    }
}
