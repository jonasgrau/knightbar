import ChessCore
import Foundation

/// Exercises the app model, including its delayed reply and UserDefaults persistence.
@main
struct PuzzleModelRegression {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor
    static func main() async throws {
        for moveCount in [1, 3, 2] {
            try await solvedPuzzleSurvivesReload(moveCount: moveCount)
        }
        try await puzzleFetchRegressions()
        print("PuzzleModel persistence regressions passed (solver and opponent endings).")
    }

    @MainActor
    static func solvedPuzzleSurvivesReload(moveCount: Int) async throws {
        let suite = "Knightbar.PuzzleModelRegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let folder = FileManager.default.temporaryDirectory.appending(path: suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        defaults.set(Puzzle.Source.chessCom.rawValue, forKey: "puzzleSource")
        let pgn = ["1. e4", "1. e4 e5", "1. e4 e5 2. Nf3"][moveCount - 1]
        let data = try JSONSerialization.data(withJSONObject: [
            "title": "Persistence regression",
            "url": "https://www.chess.com/daily/regression-\(moveCount)",
            "fen": Position.start.fen,
            "pgn": pgn + " *",
        ])
        let cache = PuzzleCache(folder: folder)
        try cache.store(data, for: .chessCom, fetchedAt: .now)
        let model = PuzzleModel(cache: cache, defaults: defaults)
        model.refreshIfNeeded()
        guard let puzzle = model.session?.puzzle else { throw Failure(description: "Puzzle not loaded") }
        for (index, move) in puzzle.solution.enumerated() where index.isMultiple(of: 2) {
            model.move(from: move.from, to: move.to)
            if model.session?.state == .awaitingReply {
                guard !model.wasSolvedBefore else {
                    throw Failure(description: "An unfinished puzzle was recorded as solved")
                }
                let deadline = ContinuousClock.now.advanced(by: .seconds(5))
                while model.session?.state == .awaitingReply, ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
        }
        guard model.session?.state == .solved else { throw Failure(description: "Puzzle did not finish") }
        guard model.wasSolvedBefore else {
            throw Failure(description: "Solved puzzle with \(moveCount) moves was not recorded")
        }
        guard let saved = defaults.data(forKey: "solvedPuzzles"),
              try JSONDecoder().decode(SolvedPuzzles.self, from: saved).contains(puzzle) else {
            throw Failure(description: "Solved puzzle was not persisted")
        }
        let reloaded = PuzzleModel(cache: cache, defaults: defaults)
        reloaded.refreshIfNeeded()
        guard reloaded.wasSolvedBefore, reloaded.statusText.contains("solved before") else {
            throw Failure(description: "Reload lost the solved puzzle")
        }
        print("PASS: \(moveCount)-move puzzle remains solved after reload")
    }
}
