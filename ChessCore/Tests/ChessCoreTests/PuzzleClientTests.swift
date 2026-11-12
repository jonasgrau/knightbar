import ChessCore
import Foundation
import Testing

/// A clock the test can move forward.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)
    var now: Date { lock.withLock { current } }
    func advance(by seconds: TimeInterval) { lock.withLock { current += seconds } }
}

@Suite struct PuzzleClientTests {
    private func client(_ transport: FakeHTTPTransport, clock: TestClock = TestClock()) -> PuzzleClient {
        PuzzleClient(transport: transport, userAgent: "TestApp/1.0", now: { clock.now })
    }

    @Test func lichessPuzzleIsFetchedFromTheDailyEndpoint() async throws {
        let transport = FakeHTTPTransport([ok(PuzzleFixtures.lichess)])
        let data = try await client(transport).dailyPuzzleData(from: .lichess)
        #expect(try Puzzle(lichessJSON: data).id == "ioglh")
        #expect(transport.requests == [HTTPRequest(
            url: URL(string: "https://lichess.org/api/puzzle/daily")!,
            headers: ["Accept": "application/json", "User-Agent": "TestApp/1.0"])])
    }

    @Test func chessComPuzzleIsFetchedFromThePublishedDataAPI() async throws {
        let transport = FakeHTTPTransport([ok(PuzzleFixtures.chessCom)])
        let data = try await client(transport).dailyPuzzleData(from: .chessCom)
        #expect(try Puzzle(chessComJSON: data).id == "2026-11-11")
        #expect(transport.requests.map(\.url) == [URL(string: "https://api.chess.com/pub/puzzle")!])
    }

    @Test func serverErrorIsReportedWithItsStatus() async {
        let client = client(FakeHTTPTransport([status(503)]))
        await #expect(throws: PuzzleClientError.http(503)) { try await client.dailyPuzzleData(from: .lichess) }
    }

    @Test func connectionFailureIsReportedAsOffline() async {
        let client = client(FakeHTTPTransport([.failure(URLError(.notConnectedToInternet))]))
        await #expect(throws: PuzzleClientError.offline) { try await client.dailyPuzzleData(from: .lichess) }
    }

    @Test func tooManyRequestsBlocksTheHostForAMinute() async throws {
        let clock = TestClock()
        let transport = FakeHTTPTransport([status(429), ok(PuzzleFixtures.lichess)])
        let client = client(transport, clock: clock)
        let blockedUntil = clock.now.addingTimeInterval(60)

        await #expect(throws: PuzzleClientError.rateLimited(until: blockedUntil)) {
            try await client.dailyPuzzleData(from: .lichess)
        }
        clock.advance(by: 59)
        await #expect(throws: PuzzleClientError.rateLimited(until: blockedUntil)) {
            try await client.dailyPuzzleData(from: .lichess)
        }
        #expect(transport.requests.count == 1)

        clock.advance(by: 1)
        _ = try await client.dailyPuzzleData(from: .lichess)
        #expect(transport.requests.count == 2)
    }

    @Test func rateLimitOnOneHostDoesNotBlockTheOther() async throws {
        let transport = FakeHTTPTransport([status(429), ok(PuzzleFixtures.chessCom)])
        let client = client(transport)
        await #expect(throws: PuzzleClientError.self) { try await client.dailyPuzzleData(from: .lichess) }
        _ = try await client.dailyPuzzleData(from: .chessCom)
        #expect(transport.requests.count == 2)
    }
}

@Suite struct PuzzleCacheTests {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "chesscore-puzzles-\(UUID().uuidString)")
    }

    @Test func storedResponseIsReadBackPerSource() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = PuzzleCache(folder: folder)
        #expect(cache.entry(for: .lichess) == nil)

        let fetched = Date(timeIntervalSince1970: 1_800_000_000)
        try cache.store(Data(PuzzleFixtures.lichess.utf8), for: .lichess, fetchedAt: fetched)
        let entry = try #require(cache.entry(for: .lichess))
        #expect(entry.data == Data(PuzzleFixtures.lichess.utf8))
        #expect(entry.fetchedAt == fetched)
        #expect(cache.entry(for: .chessCom) == nil)
    }

    @Test func entryIsFreshForFifteenMinutes() {
        let fetched = Date(timeIntervalSince1970: 1_800_000_000)
        let entry = PuzzleCache.Entry(data: Data(), fetchedAt: fetched)
        #expect(entry.isFresh(at: fetched.addingTimeInterval(14 * 60)))
        #expect(!entry.isFresh(at: fetched.addingTimeInterval(15 * 60)))
    }

    @Test func unreadableCacheFileCountsAsMissing() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = PuzzleCache(folder: folder)
        try cache.store(Data("x".utf8), for: .lichess, fetchedAt: .now)
        try Data("{broken".utf8).write(to: folder.appending(path: "puzzle-lichess.json"))
        #expect(cache.entry(for: .lichess) == nil)
    }
}
