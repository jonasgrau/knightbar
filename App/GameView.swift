import ChessCore
import SwiftUI

/// The board of the game against the computer or a second player.
struct GameBoard: View {
    let model: GameModel

    var body: some View {
        BoardView(model: model)
            .overlay {
                if let pending = model.session.pendingPromotion {
                    PromotionPicker(
                        color: pending.color,
                        onChoose: model.promote(to:),
                        onCancel: model.cancelPromotion)
                }
            }
    }
}

struct GameStatus: View {
    let model: GameModel

    var body: some View {
        Text(model.statusText)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        if model.isThinking {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        }
        if model.engineFailed {
            Button("Retry", action: model.retryEngine)
                .controlSize(.small)
        }
    }
}

struct GameToolbar: View {
    let model: GameModel

    var body: some View {
        Button("New Game", action: model.newGame)
        ToolButton("Take Back Move", symbol: "arrow.uturn.backward", action: model.undo)
            .disabled(!model.session.canUndo)
        ToolButton("Resign", symbol: "flag", action: model.resign)
            .disabled(model.game.status.isOver)
        ToolButton("Flip Board", symbol: "arrow.up.arrow.down") { model.isFlipped.toggle() }
        ToolButton("Analyze on Lichess", symbol: "magnifyingglass", action: model.analyzeOnLichess)
            .disabled(model.game.moves.isEmpty)
            .contextMenu {
                Button("Copy PGN", action: model.copyPGN)
            }
    }
}
