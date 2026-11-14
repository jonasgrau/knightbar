import ChessCore
import Foundation

private struct TestTokens: TokenStore {
    func load() -> String? { "test-token" }
    func save(_ token: String) {}
    func delete() {}
}

@MainActor
private struct UnusedAuthenticator: WebAuthenticator {
    func authenticate(at url: URL, callbackScheme: String) async throws -> URL {
        throw CancellationError()
    }
}

private actor TestTransport: HTTPTransport {
    enum MoveResponse: CaseIterable { case offline, rejected, accepted }
    let moveResponse: MoveResponse
    let gameLines = AsyncThrowingStream<String, any Error>.makeStream()
    let eventLines = AsyncThrowingStream<String, any Error>.makeStream()
    private(set) var moveSent = false

    init(_ moveResponse: MoveResponse) { self.moveResponse = moveResponse }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let body: String
        switch request.url.path {
        case "/api/account":
            body = #"{"id":"kenneth","username":"Kenneth"}"#
        case "/api/account/playing":
            body = LichessFixtures.playing
        case "/api/board/game/p8Jy2ayw/move/g1f3":
            moveSent = true
            switch moveResponse {
            case .offline: throw URLError(.notConnectedToInternet)
            case .rejected:
                return HTTPResponse(status: 400, body: Data(#"{"error":"Move refused"}"#.utf8))
            case .accepted: body = #"{"ok":true}"#
            }
        default: throw URLError(.unsupportedURL)
        }
        return HTTPResponse(status: 200, body: Data(body.utf8))
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStream {
        if request.url.path == "/api/stream/event" {
            return HTTPStream(status: 200, lines: eventLines.stream)
        }
        guard request.url.path == "/api/board/game/stream/p8Jy2ayw" else {
            throw URLError(.unsupportedURL)
        }
        let full = LichessFixtures.gameFull
            .replacingOccurrences(of: "qP8XaFtN", with: "p8Jy2ayw")
            .replacingOccurrences(of: #""moves":"""#, with: #""moves":"e2e4 e7e5""#)
        gameLines.continuation.yield(full)
        return HTTPStream(status: 200, lines: gameLines.stream)
    }

    func report(moves: String) {
        gameLines.continuation.yield(LichessFixtures.state(moves: moves))
    }

    func finish() {
        gameLines.continuation.finish()
        eventLines.continuation.finish()
    }
}

@main
struct LichessModelRegression {
    private struct NoStoredToken: TokenStore {
        func load() -> String? { nil }
        func save(_ token: String) {}
        func delete() {}
    }
    struct Failure: Error, CustomStringConvertible { let description: String }

    @MainActor
    static func waitFor(_ description: String, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard condition() else { throw Failure(description: "Timed out: \(description)") }
    }

    @MainActor
    static func main() async throws {
        try await challengeDraftSurvivesFailure()
        for response in TestTransport.MoveResponse.allCases {
            try await notificationsFollowServerMoves(response)
        }
        try await notificationPreferenceIsShared()
        print("LichessModel notification regressions passed.")
    }

    @MainActor
    private static func challengeDraftSurvivesFailure() async throws {
        let suite = "Knightbar.ChallengeDraft.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let transport = ControlledHTTPTransport()
        let client = LichessClient(transport: transport, userAgent: "RegressionTest")
        await client.setToken("test-token")
        let model = LichessModel(client: client,
                                 tokens: NoStoredToken(), authenticator: UnusedAuthenticator(), defaults: defaults)
        model.challengeUsername = "friend"
        model.challengeDays = 7
        model.challengeColor = .black
        let path = "/api/challenge/friend"
        let first = Task { await model.sendChallenge() }
        try await waitForRegression("challenge request") { await transport.count(path) == 1 }
        try requireRegression(model.isSendingChallenge, "Missing pending challenge state")
        await model.sendChallenge()
        try requireRegression(await transport.count(path) == 1, "Duplicate challenge was sent")
        await transport.fail(path)
        await first.value
        try requireRegression(model.challengeUsername == "friend" && model.challengeDays == 7 && model.challengeColor == .black,
                              "Failed challenge discarded the form")
        try requireRegression(model.challengeError != nil && !model.isSendingChallenge,
                              "Challenge failure did not allow retry")
        let retry = Task { await model.sendChallenge() }
        try await waitForRegression("challenge retry") { await transport.count(path) == 2 }
        await transport.reply(path, body: #"{"challenge":{"id":"test"}}"#)
        await retry.value
        try requireRegression(model.challengeUsername.isEmpty && model.challengeError == nil && model.challengeSuccess != nil,
                              "Successful challenge did not clear the name and confirm success")
        await transport.finish()
        print("PASS: challenge failure retains draft, duplicate guard and successful retry")
    }

    @MainActor
    private static func notificationPreferenceIsShared() async throws {
        let suite = "Knightbar.SharedNotificationRegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // Seed the existing on-disk key to guard compatibility with installed versions.
        defaults.set(true, forKey: "lichessNotifyOnMove")
        defaults.set("shared-user", forKey: "chessComUsername")
        let lichess = LichessModel(tokens: NoStoredToken(), authenticator: UnusedAuthenticator(),
                                   defaults: defaults, requestNotificationPermission: { true }, notify: { _, _ in })
        try requireRegression(lichess.notifiesOnMove, "Existing notification preference was not loaded")
        let transport = ControlledHTTPTransport()
        var notifications: [String] = []
        let chessCom = ChessComModel(client: ChessComClient(transport: transport, userAgent: "RegressionTest"),
                                     defaults: defaults, notify: { notifications.append($0) })
        let path = "/pub/player/shared-user/games/to-move"
        for index in 1...3 {
            if index > 1 {
                lichess.notifiesOnMove = index == 3
                chessCom.refresh()
            }
            try await waitForRegression("Chess.com refresh \(index)") { await transport.count(path) == index }
            await transport.reply(path, body: #"{"games":[{"url":"https://www.chess.com/game/daily/\#(index)"}]}"#)
            try await waitForRegression("Chess.com result \(index)") { !chessCom.isLoading }
            try requireRegression(notifications == (index == 3 ? ["3"] : []),
                                  "Chess.com did not follow the shared notification toggle")
        }
        lichess.notifiesOnMove = false
        try requireRegression(!defaults.bool(forKey: "lichessNotifyOnMove"), "Existing notification key was not updated")
        chessCom.username = ""
        await transport.finish()
        print("PASS: existing notification preference and shared Lichess/Chess.com toggle")
    }

    @MainActor
    private static func notificationsFollowServerMoves(_ response: TestTransport.MoveResponse) async throws {
        let suite = "Knightbar.LichessModelRegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "lichessNotifyOnMove")
        let transport = TestTransport(response)
        var notifications: [String] = []
        let model = LichessModel(
            client: LichessClient(transport: transport, userAgent: "RegressionTest"),
            tokens: TestTokens(), authenticator: UnusedAuthenticator(), defaults: defaults,
            requestNotificationPermission: { true },
            notify: { _, gameID in notifications.append(gameID) })
        defer { model.signOut() }
        try await waitFor("initial game list") { !model.overview.games.isEmpty }
        guard notifications.isEmpty else { throw Failure(description: "Initial load notified") }
        model.open(model.overview.games[0])
        try await waitFor("initial board") { model.session?.game.moves.count == 2 }
        model.move(from: Square("g1")!, to: Square("f3")!)

        if response == .accepted {
            // Wait for the POST before acknowledging it through the game stream.
            let deadline = ContinuousClock.now.advanced(by: .seconds(5))
            while await !transport.moveSent, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard await transport.moveSent else { throw Failure(description: "Move was not sent") }
            await transport.report(moves: "e2e4 e7e5 g1f3")
            try await waitFor("move acknowledgement") { model.openGame?.game.moves.count == 3 }
            guard notifications.isEmpty else { throw Failure(description: "Own move notified") }
            await transport.report(moves: "e2e4 e7e5 g1f3 b8c6")
            try await waitFor("opponent reply") { model.session?.game.moves.count == 4 }
            guard notifications == ["p8Jy2ayw"] else {
                throw Failure(description: "Opponent reply did not notify exactly once")
            }
        } else {
            try await waitFor("failed move rollback") { model.message?.hasPrefix("The move was not sent.") == true }
            guard model.session?.game.moves.count == 2, model.isMyTurnAnywhere,
                  model.canSelect(Square("g1")!) else {
                throw Failure(description: "Failed move did not restore the board and turn")
            }
            guard notifications.isEmpty else {
                throw Failure(description: "Failed \(response) move falsely notified an opponent move")
            }
        }
        model.closeGame()
        await transport.finish()
        print("PASS: \(response) move notification behavior")
    }
}
