import ChessCore
import Foundation

@MainActor
func puzzleFetchRegressions() async throws {
    for cached in [false, true] {
        for oldFails in [false, true] {
            let suite = "Knightbar.PuzzleFetchRegression.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let folder = FileManager.default.temporaryDirectory.appending(path: suite)
            defer {
                defaults.removePersistentDomain(forName: suite)
                try? FileManager.default.removeItem(at: folder)
            }
            let transport = ControlledHTTPTransport()
            let cache = PuzzleCache(folder: folder)
            if cached {
                try cache.store(Data(PuzzleFixtures.chessCom.utf8), for: .chessCom,
                                fetchedAt: .now.addingTimeInterval(-3600))
            }
            let model = PuzzleModel(client: PuzzleClient(transport: transport, userAgent: "RegressionTest"),
                                    cache: cache, defaults: defaults)
            model.refreshIfNeeded()
            try await waitForRegression("initial puzzle request") { await transport.count("/api/puzzle/daily") == 1 }
            model.source = .chessCom
            try await waitForRegression("replacement puzzle request") { await transport.count("/pub/puzzle") == 1 }
            model.refreshIfNeeded()
            if oldFails { await transport.fail("/api/puzzle/daily") }
            else { await transport.reply("/api/puzzle/daily", body: PuzzleFixtures.lichess) }
            try await remainsTrue("Old puzzle response changed the replacement's loading state") {
                model.isLoading && model.loadError == nil && model.session?.puzzle.source != .lichess
            }
            await transport.reply("/pub/puzzle", body: PuzzleFixtures.chessCom)
            try await waitForRegression("replacement puzzle loaded") {
                !model.isLoading && model.session?.puzzle.source == .chessCom
            }
            try requireRegression(await transport.count("/pub/puzzle") == 1, "Duplicate puzzle fetch")
            await transport.finish()
        }
    }
    try await puzzleSourceRoundTrip()
    print("PASS: puzzle source switches load immediately and ignore cancelled responses")
}

@MainActor
private func puzzleSourceRoundTrip() async throws {
    let suite = "Knightbar.PuzzleRoundTrip.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let folder = FileManager.default.temporaryDirectory.appending(path: suite)
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }
    let transport = ControlledHTTPTransport()
    let model = PuzzleModel(client: PuzzleClient(transport: transport, userAgent: "RegressionTest"),
                            cache: PuzzleCache(folder: folder), defaults: defaults)
    model.refreshIfNeeded()
    try await waitForRegression("first Lichess request") { await transport.count("/api/puzzle/daily") == 1 }
    model.source = .chessCom
    try await waitForRegression("Chess.com request") { await transport.count("/pub/puzzle") == 1 }
    model.source = .lichess
    try await waitForRegression("second Lichess request") { await transport.count("/api/puzzle/daily") == 2 }
    await transport.reply("/api/puzzle/daily", body: PuzzleFixtures.lichess)
    await transport.fail("/pub/puzzle")
    try await remainsTrue("Cancelled same-source response was accepted") {
        model.isLoading && model.session == nil && model.loadError == nil
    }
    await transport.reply("/api/puzzle/daily", body: PuzzleFixtures.lichess)
    try await waitForRegression("latest Lichess request") { !model.isLoading && model.session != nil }
    await transport.finish()
}
