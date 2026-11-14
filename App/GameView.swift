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
        if model.playsComputer && model.engineFailed {
            Button("Retry", action: model.retryEngine)
                .controlSize(.small)
        }
    }
}

struct GameToolbar: View {
    @Bindable var model: GameModel

    var body: some View {
        Button("New Game", action: model.requestNewGame)
            .fixedSize()
            .confirmationDialog("Start a new game?", isPresented: $model.confirmsNewGame, titleVisibility: .visible) {
                Button("Start New Game", role: .destructive, action: model.newGame)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your current game will be replaced. This cannot be undone.")
            }
        ToolButton("Take Back Move", symbol: "arrow.uturn.backward", action: model.undo)
            .disabled(!model.session.canUndo)
        ToolButton("Resign", symbol: "flag", action: model.resign)
            .disabled(model.game.status.isOver)
        ToolButton("Flip Board", symbol: "arrow.up.arrow.down") { model.isFlipped.toggle() }
        Menu("Tools") {
            Button("Analyze on Lichess", action: model.analyzeOnLichess)
            Button("Copy PGN", action: model.copyPGN)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.game.moves.isEmpty)
        .help("Analyze on Lichess or copy PGN")
    }
}
