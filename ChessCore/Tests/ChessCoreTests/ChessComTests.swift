import ChessCore
import Foundation
import Testing

@Suite struct ChessComClientTests {
    /// The response of the to-move endpoint for a public account, fetched on 2026-11-12.
    static let oneGame = #"{"games":[{"url":"https://www.chess.com/game/daily/1044546360","move_by":1794728784,"last_activity":1794469584}]}"#
    static let noGames = #"{"games":[]}"#

    private func reply(_ body: String, etag: String? = nil, status: Int = 200) -> Result<HTTPResponse, URLError> {
        .success(HTTPResponse(status: status, body: Data(body.utf8), headers: etag.map { ["etag": $0] } ?? [:]))
    }

    private func client(_ transport: FakeHTTPTransport, clock: TestClock = TestClock()) -> ChessComClient {
        ChessComClient(transport: transport, userAgent: "TestApp/1.0", now: { clock.now })
    }

    private let endpoint = URL(string: "https://api.chess.com/pub/player/erik/games/to-move")!

    @Test func gamesToMoveAreFetchedAndDecoded() async throws {
        let transport = FakeHTTPTransport([reply(Self.oneGame)])
        let games = try await client(transport).gamesToMove(for: "erik")
        #expect(games == [ChessComGame(
            url: URL(string: "https://www.chess.com/game/daily/1044546360")!,
            moveBy: Date(timeIntervalSince1970: 1_794_728_784))])
        #expect(games[0].id == "1044546360")
        #expect(transport.requests == [HTTPRequest(url: endpoint, headers: ["Accept": "application/json", "User-Agent": "TestApp/1.0"])])
    }

    @Test func usernameIsTrimmedLowercasedAndEscaped() async throws {
        let transport = FakeHTTPTransport([reply(Self.noGames), reply(Self.noGames)])
        let client = client(transport)
        _ = try await client.gamesToMove(for: "  Erik ")
        _ = try await client.gamesToMove(for: "a/b c")
        #expect(transport.requests.map(\.url.absoluteString) == [
            "https://api.chess.com/pub/player/erik/games/to-move",
            "https://api.chess.com/pub/player/a%2Fb%20c/games/to-move",
        ])
    }

    @Test func emptyListMeansNoGameIsWaiting() async throws {
        #expect(try await client(FakeHTTPTransport([reply(Self.noGames)])).gamesToMove(for: "erik").isEmpty)
    }

    @Test func gameWithoutDeadlineIsAccepted() async throws {
        let body = #"{"games":[{"url":"https://www.chess.com/game/daily/7","move_by":0}]}"#
        let games = try await client(FakeHTTPTransport([reply(body)])).gamesToMove(for: "erik")
        #expect(games == [ChessComGame(url: URL(string: "https://www.chess.com/game/daily/7")!, moveBy: nil)])
    }

    @Test func secondRequestSendsTheETagAndNotModifiedReturnsTheKnownGames() async throws {
        let transport = FakeHTTPTransport([reply(Self.oneGame, etag: #"W/"abc""#), reply("", status: 304)])
        let client = client(transport)
        let first = try await client.gamesToMove(for: "erik")
        let second = try await client.gamesToMove(for: "Erik")
        #expect(second == first)
        #expect(transport.requests[0].headers["If-None-Match"] == nil)
        #expect(transport.requests[1].headers["If-None-Match"] == #"W/"abc""#)
    }

    @Test func changedAnswerReplacesTheRememberedOne() async throws {
        let transport = FakeHTTPTransport([
            reply(Self.oneGame, etag: "one"), reply(Self.noGames, etag: "two"), reply("", status: 304),
        ])
        let client = client(transport)
        _ = try await client.gamesToMove(for: "erik")
        #expect(try await client.gamesToMove(for: "erik").isEmpty)
        #expect(try await client.gamesToMove(for: "erik").isEmpty)
        #expect(transport.requests[2].headers["If-None-Match"] == "two")
    }

    @Test func etagOfOneUserIsNotSentForAnother() async throws {
        let transport = FakeHTTPTransport([reply(Self.oneGame, etag: "one"), reply(Self.noGames)])
        let client = client(transport)
        _ = try await client.gamesToMove(for: "erik")
        #expect(try await client.gamesToMove(for: "someoneelse").isEmpty)
        #expect(transport.requests[1].headers["If-None-Match"] == nil)
    }

    @Test func unknownUserIsReported() async {
        let client = client(FakeHTTPTransport([reply(#"{"code":0,"message":"User \"x\" not found."}"#, status: 404)]))
        await #expect(throws: ChessComError.userNotFound) { try await client.gamesToMove(for: "x") }
    }

    @Test func emptyUsernameIsRejectedWithoutARequest() async {
        let transport = FakeHTTPTransport([reply(Self.noGames)])
        let client = client(transport)
        await #expect(throws: ChessComError.userNotFound) { try await client.gamesToMove(for: "   ") }
        #expect(transport.requests.isEmpty)
    }

    @Test func serverErrorAndBrokenBodyAreReported() async {
        let failing = client(FakeHTTPTransport([reply("", status: 502)]))
        await #expect(throws: ChessComError.http(502)) { try await failing.gamesToMove(for: "erik") }
        let broken = client(FakeHTTPTransport([reply("<html>")]))
        await #expect(throws: ChessComError.invalidResponse) { try await broken.gamesToMove(for: "erik") }
    }

    @Test func connectionFailureIsReportedAsOffline() async {
        let client = client(FakeHTTPTransport([.failure(URLError(.notConnectedToInternet))]))
        await #expect(throws: ChessComError.offline) { try await client.gamesToMove(for: "erik") }
    }

    @Test func tooManyRequestsPausesForAMinute() async throws {
        let clock = TestClock()
        let transport = FakeHTTPTransport([reply("", status: 429), reply(Self.noGames)])
        let client = client(transport, clock: clock)
        let until = clock.now.addingTimeInterval(60)
        await #expect(throws: ChessComError.rateLimited(until: until)) { try await client.gamesToMove(for: "erik") }
        clock.advance(by: 59)
        await #expect(throws: ChessComError.rateLimited(until: until)) { try await client.gamesToMove(for: "erik") }
        #expect(transport.requests.count == 1)
        clock.advance(by: 1)
        _ = try await client.gamesToMove(for: "erik")
        #expect(transport.requests.count == 2)
    }

    @Test func headerLookupIgnoresCase() {
        let response = HTTPResponse(status: 200, body: Data(), headers: ["ETag": "x"])
        #expect(response.header("etag") == "x")
        #expect(response.header("ETAG") == "x")
        #expect(response.header("other") == nil)
    }
}

@Suite struct ChessComGameTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func game(secondsLeft: TimeInterval?) -> ChessComGame {
        ChessComGame(url: URL(string: "https://www.chess.com/game/daily/1")!, moveBy: secondsLeft.map { now.addingTimeInterval($0) })
    }

    static let cases: [(Double, String)] = [
        (259_300, "3 days left"),
        (172_800, "2 days left"),
        (90_000, "1 day left"),
        (86_340, "23 hours left"),
        (3_600, "1 hour left"),
        (3_570, "59 minutes left"),
        (90, "1 minute left"),
        (20, "Less than a minute left"),
        (0, "Time is up"),
        (-500, "Time is up"),
    ]

    @Test(arguments: cases)
    func remainingTimeIsDescribedInTheLargestFittingUnit(seconds: Double, text: String) {
        #expect(game(secondsLeft: seconds).timeLeftText(at: now) == text)
    }

    @Test func gameWithoutDeadlineHasNoTimeText() {
        #expect(game(secondsLeft: nil).timeLeftText(at: now) == nil)
    }
}
