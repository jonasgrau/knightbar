import ChessCore
import Foundation
import Testing

@Suite struct LichessClientTests {
    private func client(_ transport: FakeHTTPTransport, token: String? = "lip_secret", clock: TestClock = TestClock()) async -> LichessClient {
        let client = LichessClient(transport: transport, userAgent: "TestApp/1.0", now: { clock.now })
        await client.setToken(token)
        return client
    }

    private func url(_ path: String) -> URL { URL(string: "https://lichess.org" + path)! }

    private let authorized = ["Accept": "application/json", "User-Agent": "TestApp/1.0", "Authorization": "Bearer lip_secret"]

    @Test func codeIsExchangedForAToken() async throws {
        let transport = FakeHTTPTransport([ok(#"{"token_type":"Bearer","access_token":"lip_new","expires_in":31536000}"#)])
        let oauth = OAuthRequest(clientID: "knightbar", redirectURI: "knightbar://oauth", scopes: ["board:play"],
                                 randomBytes: { Array(repeating: 1, count: $0) })
        let token = try await client(transport, token: nil).exchangeCode("liu_code", for: oauth)
        #expect(token == "lip_new")

        let request = try #require(transport.requests.first)
        #expect(request.method == "POST")
        #expect(request.url == url("/api/token"))
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
        #expect(request.headers["Authorization"] == nil)
        let form = Dictionary(uniqueKeysWithValues: String(decoding: request.body ?? Data(), as: UTF8.self)
            .split(separator: "&").map { pair in
                let parts = pair.split(separator: "=", maxSplits: 1)
                return (String(parts[0]), String(parts[1]).removingPercentEncoding ?? "")
            })
        #expect(form == [
            "grant_type": "authorization_code", "code": "liu_code", "code_verifier": oauth.codeVerifier,
            "redirect_uri": "knightbar://oauth", "client_id": "knightbar",
        ])
    }

    @Test func accountReturnsIDAndName() async throws {
        let transport = FakeHTTPTransport([ok(#"{"id":"bobby","username":"Bobby","perfs":{}}"#)])
        let account = try await client(transport).account()
        #expect(account == LichessAccount(id: "bobby", username: "Bobby"))
        #expect(transport.requests == [HTTPRequest(url: url("/api/account"), headers: authorized)])
    }

    @Test func moveIsPostedInUCI() async throws {
        let transport = FakeHTTPTransport([ok()])
        try await client(transport).move(Move(uci: "e7e8q")!, inGame: "abcd1234")
        #expect(transport.requests == [HTTPRequest(method: "POST", url: url("/api/board/game/abcd1234/move/e7e8q"), headers: authorized)])
    }

    @Test func resignAndDrawUseTheBoardEndpoints() async throws {
        let transport = FakeHTTPTransport([ok(), ok(), ok()])
        let client = await client(transport)
        try await client.resign(game: "abcd1234")
        try await client.answerDraw(true, inGame: "abcd1234")
        try await client.answerDraw(false, inGame: "abcd1234")
        #expect(transport.requests.map(\.url) == [
            url("/api/board/game/abcd1234/resign"),
            url("/api/board/game/abcd1234/draw/yes"),
            url("/api/board/game/abcd1234/draw/no"),
        ])
        #expect(transport.requests.allSatisfy { $0.method == "POST" })
    }

    @Test func challengesAreAcceptedDeclinedAndCreated() async throws {
        let transport = FakeHTTPTransport([ok(), ok(), ok(#"{"id":"newChall","url":"https://lichess.org/newChall","status":"created"}"#)])
        let client = await client(transport)
        try await client.acceptChallenge("qUfdwN17")
        try await client.declineChallenge("qUfdwN17")
        try await client.challenge(user: "Aaron", daysPerMove: 3, color: .black)
        #expect(transport.requests.map(\.url) == [
            url("/api/challenge/qUfdwN17/accept"),
            url("/api/challenge/qUfdwN17/decline"),
            url("/api/challenge/Aaron"),
        ])
        let body = String(decoding: transport.requests[2].body ?? Data(), as: UTF8.self)
        #expect(Set(body.split(separator: "&").map(String.init)) == ["days=3", "color=black", "rated=false"])
    }

    @Test func challengeWithoutColourLeavesTheChoiceToLichess() async throws {
        let transport = FakeHTTPTransport([ok()])
        try await client(transport).challenge(user: "Aaron", daysPerMove: 1, color: nil)
        let body = String(decoding: transport.requests[0].body ?? Data(), as: UTF8.self)
        #expect(Set(body.split(separator: "&").map(String.init)) == ["days=1", "color=random", "rated=false"])
    }

    @Test func ongoingGamesAreListed() async throws {
        let transport = FakeHTTPTransport([ok(LichessFixtures.playing)])
        let games = try await client(transport).ongoingGames()
        #expect(games.map(\.id) == ["p8Jy2ayw"])
        #expect(transport.requests.map(\.url) == [url("/api/account/playing?nb=50")])
    }

    @Test func tokenIsRevoked() async throws {
        let transport = FakeHTTPTransport([status(204)])
        try await client(transport).revokeToken()
        #expect(transport.requests == [HTTPRequest(method: "DELETE", url: url("/api/token"), headers: authorized)])
    }

    @Test func requestsWithoutATokenFailBeforeReachingTheNetwork() async {
        let transport = FakeHTTPTransport([ok()])
        let client = await client(transport, token: nil)
        await #expect(throws: LichessError.unauthorized) { try await client.account() }
        #expect(transport.requests.isEmpty)
    }

    @Test func rejectedTokenIsReportedAsUnauthorized() async {
        let client = await client(FakeHTTPTransport([status(401, #"{"error":"No such token"}"#)]))
        await #expect(throws: LichessError.unauthorized) { try await client.account() }
    }

    @Test func serverErrorCarriesTheMessageFromLichess() async {
        let client = await client(FakeHTTPTransport([status(400, #"{"error":"Not your turn, or game already over"}"#)]))
        await #expect(throws: LichessError.http(400, "Not your turn, or game already over")) {
            try await client.move(Move(uci: "e2e4")!, inGame: "abcd1234")
        }
    }

    @Test func connectionFailureIsReportedAsOffline() async {
        let client = await client(FakeHTTPTransport([.failure(URLError(.timedOut))]))
        await #expect(throws: LichessError.offline) { try await client.account() }
    }

    @Test func tooManyRequestsPausesAllRequestsForAMinute() async throws {
        let clock = TestClock()
        let transport = FakeHTTPTransport([status(429), ok(#"{"id":"bobby","username":"Bobby"}"#)])
        let client = await client(transport, clock: clock)
        let until = clock.now.addingTimeInterval(60)

        await #expect(throws: LichessError.rateLimited(until: until)) { try await client.account() }
        clock.advance(by: 30)
        await #expect(throws: LichessError.rateLimited(until: until)) { try await client.resign(game: "x") }
        #expect(transport.requests.count == 1)
        clock.advance(by: 30)
        _ = try await client.account()
        #expect(transport.requests.count == 2)
    }

    @Test func eventStreamDeliversDecodedEvents() async throws {
        let transport = FakeHTTPTransport(streams: [.init(lines: [LichessFixtures.gameStart, "", LichessFixtures.challenge])])
        var events: [LichessEvent] = []
        for try await event in try await client(transport).events() { events.append(event) }
        #expect(events.count == 2)
        guard case .gameStart = events[0], case .challenge = events[1] else {
            Issue.record("unexpected events \(events)"); return
        }
        #expect(transport.requests == [HTTPRequest(url: url("/api/stream/event"), headers: [
            "Accept": "application/x-ndjson", "User-Agent": "TestApp/1.0", "Authorization": "Bearer lip_secret",
        ])])
    }

    @Test func gameStreamDeliversFullGameAndStates() async throws {
        let transport = FakeHTTPTransport(streams: [.init(lines: [LichessFixtures.gameFull, LichessFixtures.gameState, LichessFixtures.opponentGone])])
        var events: [LichessGameEvent] = []
        for try await event in try await client(transport).gameEvents(game: "qP8XaFtN") { events.append(event) }
        #expect(events.count == 3)
        #expect(transport.requests.map(\.url) == [url("/api/board/game/stream/qP8XaFtN")])
    }

    @Test func undecodableStreamLinesAreSkipped() async throws {
        let transport = FakeHTTPTransport(streams: [.init(lines: ["{broken", LichessFixtures.gameStart])])
        var count = 0
        for try await _ in try await client(transport).events() { count += 1 }
        #expect(count == 1)
    }

    @Test func streamRejectedWithUnauthorizedFailsAtOnce() async {
        let client = await client(FakeHTTPTransport(streams: [.init(status: 401)]))
        await #expect(throws: LichessError.unauthorized) { _ = try await client.events() }
    }

    @Test func streamRejectedWithTooManyRequestsStartsThePause() async {
        let clock = TestClock()
        let transport = FakeHTTPTransport([ok()], streams: [.init(status: 429)])
        let client = await client(transport, clock: clock)
        let until = clock.now.addingTimeInterval(60)
        await #expect(throws: LichessError.rateLimited(until: until)) { _ = try await client.events() }
        await #expect(throws: LichessError.rateLimited(until: until)) { try await client.resign(game: "x") }
    }

    @Test func droppedStreamEndsWithOffline() async throws {
        let transport = FakeHTTPTransport(streams: [.init(lines: [LichessFixtures.gameStart], failure: URLError(.networkConnectionLost))])
        var count = 0
        await #expect(throws: LichessError.offline) {
            for try await _ in try await client(transport).events() { count += 1 }
        }
        #expect(count == 1)
    }
}
