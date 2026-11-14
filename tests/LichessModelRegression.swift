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
        for response in TestTransport.MoveResponse.allCases {
            try await notificationsFollowServerMoves(response)
        }
        print("LichessModel notification regressions passed.")
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
