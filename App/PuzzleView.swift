import ChessCore
import SwiftUI

/// The puzzle board, or a placeholder while there is no puzzle to show.
struct PuzzleBoard: View {
    let model: PuzzleModel

    var body: some View {
        if let session = model.session {
            BoardView(model: model)
                .overlay {
                    if let pending = session.pendingPromotion {
                        PromotionPicker(
                            color: pending.color,
                            onChoose: model.promote(to:),
                            onCancel: model.cancelPromotion)
                    }
                }
        } else {
            VStack(spacing: 10) {
                if model.isLoading {
                    ProgressView()
                    Text("Loading puzzle…")
                } else {
                    Text(model.loadError ?? "No puzzle loaded.")
                        .multilineTextAlignment(.center)
                    Button("Try Again", action: model.refreshIfNeeded)
                }
            }
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
        }
    }
}

struct PuzzleStatus: View {
    let model: PuzzleModel

    var body: some View {
        Text(model.statusText)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .help(model.session?.puzzle.title ?? "")
        if model.session?.state == .solved {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityHidden(true)
        }
    }
}

struct PuzzleToolbar: View {
    let model: PuzzleModel

    var body: some View {
        ToolButton("Hint", symbol: "lightbulb", action: model.showHint)
            .disabled(model.session?.state != .solving)
        ToolButton("Start Over", symbol: "arrow.counterclockwise", action: model.startOver)
            .disabled(model.session == nil)
        ToolButton("Flip Board", symbol: "arrow.up.arrow.down") { model.isFlipped.toggle() }
        ToolButton(model.source == .lichess ? "Open on Lichess" : "Open on Chess.com", symbol: "safari",
                   action: model.openInBrowser)
            .disabled(model.session == nil)
    }
}
