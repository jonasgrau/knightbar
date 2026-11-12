import ChessCore
import Foundation
import Testing

@Suite struct OAuthTests {
    private func request(bytes: UInt8 = 7) -> OAuthRequest {
        OAuthRequest(clientID: "knightbar", redirectURI: "knightbar://oauth", scopes: ["board:play"],
                     randomBytes: { Array(repeating: bytes, count: $0) })
    }

    @Test func challengeMatchesTheExampleFromRFC7636() {
        #expect(OAuthRequest.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
            == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierAndStateAreURLSafeAndLongEnough() {
        let request = OAuthRequest(clientID: "c", redirectURI: "r://x", scopes: [])
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(request.codeVerifier.count >= 43)
        #expect(request.codeVerifier.allSatisfy(allowed.contains))
        #expect(request.state.count >= 16)
        #expect(request.state.allSatisfy(allowed.contains))
    }

    @Test func twoRequestsDoNotShareSecrets() {
        let first = OAuthRequest(clientID: "c", redirectURI: "r://x", scopes: [])
        let second = OAuthRequest(clientID: "c", redirectURI: "r://x", scopes: [])
        #expect(first.codeVerifier != second.codeVerifier)
        #expect(first.state != second.state)
    }

    @Test func authorizationURLCarriesAllParameters() throws {
        let request = request()
        let components = try #require(URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "lichess.org")
        #expect(components.path == "/oauth")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(items == [
            "response_type": "code",
            "client_id": "knightbar",
            "redirect_uri": "knightbar://oauth",
            "code_challenge_method": "S256",
            "code_challenge": OAuthRequest.codeChallenge(for: request.codeVerifier),
            "scope": "board:play",
            "state": request.state,
        ])
    }

    @Test func callbackWithMatchingStateYieldsTheCode() throws {
        let request = request()
        let url = URL(string: "knightbar://oauth?code=liu_abc123&state=\(request.state)")!
        #expect(try request.authorizationCode(fromCallback: url) == "liu_abc123")
    }

    @Test func callbackWithForeignStateIsRejected() {
        let url = URL(string: "knightbar://oauth?code=liu_abc123&state=somethingelse")!
        #expect(throws: OAuthError.stateMismatch) { try request().authorizationCode(fromCallback: url) }
    }

    @Test func callbackWithErrorReportsDenial() {
        let request = request()
        let url = URL(string: "knightbar://oauth?error=access_denied&error_description=nope&state=\(request.state)")!
        #expect(throws: OAuthError.denied("nope")) { try request.authorizationCode(fromCallback: url) }
    }

    @Test func callbackWithoutCodeIsRejected() {
        let request = request()
        let url = URL(string: "knightbar://oauth?state=\(request.state)")!
        #expect(throws: OAuthError.missingCode) { try request.authorizationCode(fromCallback: url) }
    }
}

@Suite struct LichessEventTests {
    @Test func gameStartIsRead() throws {
        guard case .gameStart(let game) = try LichessEvent(line: LichessFixtures.gameStart) else {
            Issue.record("expected gameStart"); return
        }
        #expect(game.id == "p8Jy2ayw")
        #expect(game.color == .white)
        #expect(game.isMyTurn)
        #expect(game.opponentName == "Aaron")
        #expect(game.speed == "blitz")
        #expect(game.lastMove == nil)
        #expect(game.isBoardCompatible)
        #expect(!game.isCorrespondence)
        #expect(!game.isPlayableHere)
        #expect(game.url == URL(string: "https://lichess.org/p8Jy2ayw"))
    }

    @Test func correspondenceGameAgainstTheLichessAIIsPlayableHere() throws {
        guard case .gameStart(let game) = try LichessEvent(line: LichessFixtures.gameStartAI) else {
            Issue.record("expected gameStart"); return
        }
        #expect(game.opponentName == "Stockfish level 1")
        #expect(game.color == .black)
        #expect(game.isPlayableHere)
    }

    @Test func gameFinishIsRead() throws {
        guard case .gameFinish(let game) = try LichessEvent(line: LichessFixtures.gameFinish) else {
            Issue.record("expected gameFinish"); return
        }
        #expect(game.id == "p8Jy2ayw")
        #expect(game.lastMove == Move(uci: "e7e5"))
    }

    @Test func challengeIsRead() throws {
        guard case .challenge(let challenge) = try LichessEvent(line: LichessFixtures.challenge) else {
            Issue.record("expected challenge"); return
        }
        #expect(challenge.id == "qUfdwN17")
        #expect(challenge.challengerID == "adriana")
        #expect(challenge.challengerName == "Adriana")
        #expect(challenge.destUserName == "Gabriela")
        #expect(challenge.speed == "correspondence")
        #expect(!challenge.rated)
        #expect(challenge.isBoardCompatible)
        #expect(challenge.isIncoming(forUserID: "gabriela"))
        #expect(!challenge.isIncoming(forUserID: "adriana"))
    }

    @Test func canceledAndDeclinedChallengesCarryTheirID() throws {
        #expect(try LichessEvent(line: LichessFixtures.challengeCanceled) == .challengeCanceled(id: "pWdpCP3w"))
        #expect(try LichessEvent(line: LichessFixtures.challengeDeclined) == .challengeDeclined(id: "qUfdwN17"))
    }

    @Test func unknownEventTypesAreTolerated() throws {
        #expect(try LichessEvent(line: #"{"type":"somethingNew","x":1}"#) == .other)
    }

    @Test func brokenLineIsReported() {
        #expect(throws: LichessError.invalidResponse) { try LichessEvent(line: "{nope") }
    }

    @Test func gameStreamLinesAreRead() throws {
        guard case .full(let full) = try LichessGameEvent(line: LichessFixtures.gameFull) else {
            Issue.record("expected gameFull"); return
        }
        #expect(full.id == "qP8XaFtN")
        #expect(full.whiteID == "kenneth")
        #expect(full.blackName == "Salma")
        #expect(full.initialFEN == "startpos")
        #expect(full.state.moves.isEmpty)

        guard case .state(let state) = try LichessGameEvent(line: LichessFixtures.gameState) else {
            Issue.record("expected gameState"); return
        }
        #expect(state.moves == ["e2e4"])
        #expect(state.status == "started")
        #expect(state.winner == nil)
        #expect(try LichessGameEvent(line: LichessFixtures.opponentGone) == .other)
    }

    @Test func drawOffersAndWinnerAreRead() throws {
        let line = LichessFixtures.state(moves: "e2e4 e7e5", status: "resign", extra: #","winner":"black","wdraw":true"#)
        guard case .state(let state) = try LichessGameEvent(line: line) else {
            Issue.record("expected gameState"); return
        }
        #expect(state.winner == .black)
        #expect(state.whiteOffersDraw)
        #expect(!state.blackOffersDraw)
    }
}

@Suite struct LichessGameTests {
    private func full() throws -> LichessGameFull {
        guard case .full(let full) = try LichessGameEvent(line: LichessFixtures.gameFull) else { throw LichessError.invalidResponse }
        return full
    }

    private func state(_ moves: String, status: String = "started", extra: String = "") throws -> LichessGameState {
        guard case .state(let state) = try LichessGameEvent(line: LichessFixtures.state(moves: moves, status: status, extra: extra))
        else { throw LichessError.invalidResponse }
        return state
    }

    @Test func gameKnowsTheUsersColourAndOpponent() throws {
        let asWhite = try LichessGame(full: full(), userID: "kenneth")
        #expect(asWhite.myColor == .white)
        #expect(asWhite.opponentName == "Salma")
        #expect(asWhite.isMyTurn)
        let asBlack = try LichessGame(full: full(), userID: "salma")
        #expect(asBlack.myColor == .black)
        #expect(asBlack.opponentName == "Kenneth")
        #expect(!asBlack.isMyTurn)
    }

    @Test func gameOfOtherPlayersIsRejected() throws {
        #expect(throws: LichessError.invalidResponse) { try LichessGame(full: full(), userID: "nobody") }
    }

    @Test func stateUpdatesReplayTheMoves() throws {
        var game = try LichessGame(full: full(), userID: "kenneth")
        try game.apply(state("e2e4 e7e5 g1f3"))
        #expect(game.game.moves.map(\.uci) == ["e2e4", "e7e5", "g1f3"])
        #expect(!game.isMyTurn)
        #expect(game.result == nil)
    }

    @Test func castlingWrittenAsKingTakesRookIsUnderstood() throws {
        var game = try LichessGame(full: full(), userID: "kenneth")
        try game.apply(state("e2e4 e7e5 g1f3 b8c6 f1c4 f8c5 e1h1"))
        #expect(game.game.moves.last == Move(uci: "e1g1"))
        #expect(game.game.position[Square("f1")!] == Piece(color: .white, kind: .rook))
    }

    @Test func gameContinuesAfterARepetitionThatNobodyClaimed() throws {
        var game = try LichessGame(full: full(), userID: "kenneth")
        try game.apply(state("g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1 f6g8 e2e4"))
        #expect(game.game.moves.count == 9)
        #expect(game.result == nil)
        #expect(game.isMyTurn == false)
    }

    @Test func illegalMoveFromTheServerIsReported() throws {
        var game = try LichessGame(full: full(), userID: "kenneth")
        #expect(throws: LichessError.invalidResponse) { try game.apply(self.state("e2e5")) }
    }

    @Test func customStartingPositionIsUsed() throws {
        var full = try full()
        full.initialFEN = "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1"
        let game = try LichessGame(full: full, userID: "kenneth")
        #expect(game.game.startPosition.fen == "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1")
    }

    @Test func drawOffersAreSeenFromTheUsersSide() throws {
        var game = try LichessGame(full: full(), userID: "kenneth")
        try game.apply(state("e2e4", extra: #","bdraw":true"#))
        #expect(game.opponentOffersDraw)
        #expect(!game.iOfferDraw)
        try game.apply(state("e2e4", extra: #","wdraw":true"#))
        #expect(!game.opponentOffersDraw)
        #expect(game.iOfferDraw)
    }

    @Test(arguments: [
        ("mate", #","winner":"white""#, LichessGame.Result.won(.white), "Checkmate"),
        ("resign", #","winner":"black""#, .won(.black), "Resignation"),
        ("outoftime", #","winner":"black""#, .won(.black), "Time out"),
        ("timeout", #","winner":"white""#, .won(.white), "Opponent left"),
        ("draw", "", .draw, "Draw"),
        ("stalemate", "", .draw, "Stalemate"),
        ("aborted", "", .aborted, "Aborted"),
        ("noStart", #","winner":"white""#, .won(.white), "Game not started"),
    ])
    func finishedGameReportsItsResult(status: String, extra: String, result: LichessGame.Result, reason: String) throws {
        var game = try LichessGame(full: full(), userID: "kenneth")
        try game.apply(state("e2e4", status: status, extra: extra))
        #expect(game.result == result)
        #expect(game.resultReason == reason)
        #expect(!game.isMyTurn)
    }
}

@Suite struct LichessOverviewTests {
    private func event(_ line: String) throws -> LichessEvent { try LichessEvent(line: line) }

    @Test func startedGamesAppearAndFinishedGamesDisappear() throws {
        var overview = LichessOverview()
        overview.apply(try event(LichessFixtures.gameStart), userID: "me")
        #expect(overview.games.map(\.id) == ["p8Jy2ayw"])
        overview.apply(try event(LichessFixtures.gameStart), userID: "me")
        #expect(overview.games.count == 1)
        overview.apply(try event(LichessFixtures.gameFinish), userID: "me")
        #expect(overview.games.isEmpty)
    }

    @Test func correspondenceGamesComeFirstAndGamesOnMoveBeforeTheOthers() throws {
        var overview = LichessOverview()
        overview.apply(try event(LichessFixtures.gameStart), userID: "me")          // blitz, my turn
        overview.apply(try event(LichessFixtures.gameStartAI), userID: "me")        // correspondence, not my turn
        let third = LichessFixtures.gameStartAI.replacingOccurrences(of: "abcdefgh", with: "zzzzzzzz")
            .replacingOccurrences(of: #""isMyTurn":false"#, with: #""isMyTurn":true"#)
        overview.apply(try event(third), userID: "me")                              // correspondence, my turn
        #expect(overview.games.map(\.id) == ["zzzzzzzz", "abcdefgh", "p8Jy2ayw"])
    }

    @Test func onlyGamesPlayableHereCountForTheMenuBarDot() throws {
        var overview = LichessOverview()
        overview.apply(try event(LichessFixtures.gameStart), userID: "me")          // blitz: not played here
        #expect(!overview.isMyTurnAnywhere)
        let mine = LichessFixtures.gameStartAI.replacingOccurrences(of: #""isMyTurn":false"#, with: #""isMyTurn":true"#)
        overview.apply(try event(mine), userID: "me")
        #expect(overview.isMyTurnAnywhere)
    }

    @Test func challengesAreSplitIntoIncomingAndOutgoing() throws {
        var overview = LichessOverview()
        overview.apply(try event(LichessFixtures.challenge), userID: "gabriela")
        #expect(overview.incomingChallenges.map(\.id) == ["qUfdwN17"])
        #expect(overview.outgoingChallenges.isEmpty)

        var other = LichessOverview()
        other.apply(try event(LichessFixtures.challenge), userID: "adriana")
        #expect(other.outgoingChallenges.map(\.id) == ["qUfdwN17"])
        #expect(other.incomingChallenges.isEmpty)
    }

    @Test func canceledDeclinedAndAcceptedChallengesDisappear() throws {
        var overview = LichessOverview()
        overview.apply(try event(LichessFixtures.challenge), userID: "gabriela")
        overview.apply(.challengeDeclined(id: "qUfdwN17"), userID: "gabriela")
        #expect(overview.incomingChallenges.isEmpty)

        overview.apply(try event(LichessFixtures.challenge), userID: "gabriela")
        overview.apply(.challengeCanceled(id: "qUfdwN17"), userID: "gabriela")
        #expect(overview.incomingChallenges.isEmpty)

        // An accepted challenge becomes a game with the same id.
        overview.apply(try event(LichessFixtures.challenge), userID: "gabriela")
        let started = LichessFixtures.gameStartAI.replacingOccurrences(of: "abcdefgh", with: "qUfdwN17")
        overview.apply(try event(started), userID: "gabriela")
        #expect(overview.incomingChallenges.isEmpty)
        #expect(overview.games.map(\.id) == ["qUfdwN17"])
    }

    @Test func listOfOngoingGamesReplacesTheKnownGames() throws {
        var overview = LichessOverview()
        overview.apply(try event(LichessFixtures.gameStartAI), userID: "me")
        overview.replaceGames(try LichessGameInfo.list(fromPlayingJSON: Data(LichessFixtures.playing.utf8)))
        #expect(overview.games.map(\.id) == ["p8Jy2ayw"])
        #expect(overview.games[0].isMyTurn)
        #expect(overview.games[0].lastMove == Move(uci: "e7e5"))
        #expect(overview.isMyTurnAnywhere)
    }

    @Test func turnOfASingleGameCanBeUpdated() throws {
        var overview = LichessOverview()
        let mine = LichessFixtures.gameStartAI.replacingOccurrences(of: #""isMyTurn":false"#, with: #""isMyTurn":true"#)
        overview.apply(try event(mine), userID: "me")
        overview.setMyTurn(false, inGame: "abcdefgh")
        #expect(!overview.isMyTurnAnywhere)
    }
}
