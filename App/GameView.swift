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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                StatusMessage(text: model.statusText,
                              isError: model.playsComputer && model.engineFailed && !model.game.status.isOver)
                if model.isThinking {
                    ProgressView().controlSize(.small).scaleEffect(0.7)
                }
                if model.playsComputer && model.engineFailed && !model.game.status.isOver {
                    Button("Retry", action: model.retryEngine).controlSize(.small)
                }
            }
            Text(model.matchSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct GameToolbar: View {
    @Bindable var model: GameModel
    @State private var showsSetup = false
    @State private var setup = MatchSettings()

    var body: some View {
        Button("New Game") {
            setup = model.settings
            showsSetup = true
        }
            .fixedSize()
            .popover(isPresented: $showsSetup) {
                NewGameSetup(settings: $setup,
                             replacesGame: !model.game.moves.isEmpty && !model.game.status.isOver,
                             onCancel: { showsSetup = false }) {
                    model.startNewGame(settings: setup)
                    showsSetup = false
                }
            }
        ToolButton("Take Back Move", symbol: "arrow.uturn.backward", action: model.undo)
            .disabled(!model.session.canUndo)
        Menu("Game") {
            Button("Flip Board") { model.isFlipped.toggle() }
            Divider()
            Button("Analyze on Lichess", action: model.analyzeOnLichess)
                .disabled(model.game.moves.isEmpty)
            Button("Copy PGN", action: model.copyPGN)
                .disabled(model.game.moves.isEmpty)
            Divider()
            Button("Resign", role: .destructive, action: model.resign)
                .disabled(model.game.status.isOver)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Game actions, analysis and export")
    }
}
