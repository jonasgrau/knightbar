import ChessCore
import SwiftUI

/// The board of the Lichess game that is open.
struct LichessGameBoard: View {
    let model: LichessModel

    var body: some View {
        BoardView(model: model)
            .overlay {
                if let pending = model.session?.pendingPromotion {
                    PromotionPicker(
                        color: pending.color,
                        onChoose: model.promote(to:),
                        onCancel: model.cancelPromotion)
                }
            }
    }
}

/// The Lichess part of the Online list: the login prompt, or the user's games and challenges.
struct LichessSection: View {
    let model: LichessModel
    var body: some View {
        if model.account == nil {
            OnlineGroup(title: "Lichess") {
                Text("Play your Lichess correspondence games here.")
                    .foregroundStyle(.secondary)
                Button("Log in with Lichess", action: model.signIn)
                    .disabled(model.isSigningIn)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                section("Lichess games") {
                    if model.overview.games.isEmpty {
                        Text("No games in progress.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.overview.games) { game in
                        Button { model.open(game) } label: { gameRow(game) }
                            .buttonStyle(.plain)
                    }
                }

                if !model.overview.incomingChallenges.isEmpty || !model.overview.outgoingChallenges.isEmpty {
                    section("Lichess challenges") {
                        ForEach(model.overview.incomingChallenges) { challenge in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(challenge.challengerName)
                                    Text(Self.describe(challenge))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Accept") { model.accept(challenge) }
                                Button("Decline") { model.decline(challenge) }
                            }
                        }
                        ForEach(model.overview.outgoingChallenges) { challenge in
                            Text("Waiting for \(challenge.destUserName ?? "an answer")")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        OnlineGroup(title: title, content: content)
    }

    private func gameRow(_ game: LichessGameInfo) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(game.isMyTurn && game.isPlayableHere ? Color.accentColor : .clear)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(game.opponentName)
                Text(Self.describe(game))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: game.isPlayableHere ? "chevron.right" : "arrow.up.right.square")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    private static func describe(_ game: LichessGameInfo) -> String {
        if game.isPlayableHere { return game.isMyTurn ? "Your move" : "Waiting for opponent" }
        return "\(game.speed.capitalized) – opens on Lichess"
    }

    private static func describe(_ challenge: LichessChallenge) -> String {
        let pace = challenge.daysPerTurn.map { "\($0) day\($0 == 1 ? "" : "s") per move" } ?? challenge.speed.capitalized
        return "\(pace), \(challenge.rated ? "rated" : "casual")"
    }
}

/// The form for challenging another Lichess player to a correspondence game.
struct LichessChallengeForm: View {
    @Bindable var model: LichessModel

    private static let dayChoices = [1, 2, 3, 5, 7, 10, 14]

    var body: some View {
        OnlineGroup(title: "Challenge a friend on Lichess") {
            TextField("Lichess username", text: $model.challengeUsername)
                .textFieldStyle(.roundedBorder)
                .onSubmit(sendChallenge)
            HStack {
                Picker("Days per move", selection: $model.challengeDays) {
                    ForEach(Self.dayChoices, id: \.self) { Text("\($0) day\($0 == 1 ? "" : "s") per move").tag($0) }
                }
                Picker("Your colour", selection: $model.challengeColor) {
                    Text("Random").tag(PieceColor?.none)
                    Text("White").tag(PieceColor?.some(.white))
                    Text("Black").tag(PieceColor?.some(.black))
                }
            }
            .labelsHidden()
            Button(model.isSendingChallenge ? "Sending…" : "Send Challenge", action: sendChallenge)
                .disabled(model.challengeUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let error = model.challengeError {
                StatusMessage(text: error, isError: true)
            } else if let success = model.challengeSuccess {
                Text(success)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(model.isSendingChallenge)
    }

    private func sendChallenge() {
        Task { await model.sendChallenge() }
    }
}

/// Toolbar buttons while a Lichess game is open.
struct LichessGameToolbar: View {
    let model: LichessModel
    @State private var confirmsResign = false

    var body: some View {
        ToolButton("Back to Games", symbol: "chevron.left") {
            confirmsResign = false
            model.closeGame()
        }
        if confirmsResign {
            // Resigning a real game cannot be undone, so it takes a second click.
            Button("Resign?", role: .destructive) {
                confirmsResign = false
                model.resign()
            }
            Button("Cancel") { confirmsResign = false }
        } else {
            let isOver = model.openGame?.result != nil || model.openGame == nil
            if model.openGame?.opponentOffersDraw == true {
                Button("Accept Draw", action: model.offerOrAcceptDraw)
                ToolButton("Decline Draw", symbol: "xmark", action: model.declineDraw)
            }
            Menu("Game") {
                Button("Flip Board") { model.isFlipped.toggle() }
                Button("Open on Lichess", action: model.openInBrowser)
                Divider()
                Button(model.openGame?.iOfferDraw == true ? "Draw Offered" : "Offer Draw",
                       action: model.offerOrAcceptDraw)
                    .disabled(isOver || model.openGame?.iOfferDraw == true || model.openGame?.opponentOffersDraw == true)
                Button("Resign…", role: .destructive) { confirmsResign = true }
                    .disabled(isOver)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Online game actions")
        }
    }
}
