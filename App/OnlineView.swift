import ChessCore
import SwiftUI

/// The Online tab's main area: the open Lichess game, or the list of everything that is going on.
struct OnlineBoard: View {
    let lichess: LichessModel
    let chessCom: ChessComModel

    var body: some View {
        if lichess.openGameInfo != nil {
            LichessGameBoard(model: lichess)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Everything that may be waiting for a move comes first, the challenge form last.
                    LichessSection(model: lichess)
                    Divider()
                    ChessComSection(model: chessCom)
                    if lichess.account != nil {
                        Divider()
                        LichessChallengeForm(model: lichess)
                    }
                }
                .controlSize(.small)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            .aspectRatio(1, contentMode: .fit)
        }
    }
}

/// A titled group in the Online list.
struct OnlineGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
    }
}

/// Username and the Chess.com games waiting for a move.
private struct ChessComSection: View {
    let model: ChessComModel
    @State private var name = ""

    var body: some View {
        OnlineGroup(title: "Chess.com") {
            HStack {
                TextField("Chess.com username", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.username = name.trimmingCharacters(in: .whitespaces) }
                if name.trimmingCharacters(in: .whitespaces) != model.username {
                    Button("Save") { model.username = name.trimmingCharacters(in: .whitespaces) }
                }
            }

            if let message = model.message {
                Text(message)
                    .foregroundStyle(.secondary)
            } else if !model.hasUsername {
                Text("Enter your username to see where it is your move.")
                    .foregroundStyle(.secondary)
            } else if model.games.isEmpty {
                Text(model.isLoading ? "Checking…" : "No games are waiting for your move.")
                    .foregroundStyle(.secondary)
            }

            ForEach(model.games) { game in
                Button { model.open(game) } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Daily game – your move")
                            if let left = game.timeLeftText(at: .now) {
                                Text(left)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Open on Chess.com")
            }
        }
        .onAppear { name = model.username }
    }
}

struct OnlineStatus: View {
    let lichess: LichessModel
    let chessCom: ChessComModel

    private var text: String {
        // An open game and Lichess problems speak for themselves.
        if lichess.openGameInfo != nil || lichess.message != nil || lichess.isSigningIn { return lichess.statusText }
        let waiting = lichess.waitingGameCount + chessCom.games.count
        if waiting > 0 { return "Your move in \(waiting) game\(waiting == 1 ? "" : "s")" }
        return lichess.account?.username ?? "Online"
    }

    var body: some View {
        Text(text)
            .font(.callout.weight(.medium))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .help(text)
        if lichess.isSigningIn || (lichess.openGameInfo != nil && lichess.openGame == nil) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
        }
    }
}

struct OnlineToolbar: View {
    let lichess: LichessModel
    let chessCom: ChessComModel

    var body: some View {
        if lichess.openGameInfo != nil {
            LichessGameToolbar(model: lichess)
        } else {
            ToolButton("Refresh", symbol: "arrow.clockwise") {
                chessCom.refresh()
                Task { await lichess.refreshGames() }
            }
            if lichess.account != nil {
                Button("Log Out of Lichess", action: lichess.signOut)
            }
        }
    }
}
