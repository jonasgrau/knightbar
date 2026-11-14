import ChessCore
import Foundation

@MainActor
func gamePGNRegressions() throws {
    let suite = "Knightbar.GamePGNRegression.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let folder = FileManager.default.temporaryDirectory.appending(path: suite)
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }
    let model = GameModel(store: SavedGameStore(fileURL: folder.appending(path: "game.json")),
                          defaults: defaults)
    model.settings.opponent = .human
    model.move(from: Square("e2")!, to: Square("e4")!)
    let cases = [
        ("2026-11-15T01:00:00Z", "America/New_York", "2026.11.14"),
        ("2026-11-14T23:30:00Z", "Europe/Berlin", "2026.11.15"),
        ("2027-01-01T01:00:00Z", "America/New_York", "2026.12.31"),
        ("2026-12-31T23:30:00Z", "Europe/Berlin", "2027.01.01"),
        ("2026-11-14T12:00:00Z", "GMT", "2026.11.14"),
    ]
    for (timestamp, zone, expected) in cases {
        let instant = ISO8601DateFormatter().date(from: timestamp)!
        let pgn = model.pgn(at: instant, timeZone: TimeZone(identifier: zone)!)
        try requireRegression(pgn.contains("[Date \"\(expected)\"]"),
                              "PGN date in \(zone) should be \(expected): \(pgn)")
        let restored = try PGNReader.read(pgn)
        try requireRegression(restored.moves == model.game.moves, "PGN lost the game's moves")
        print("PASS: PGN date \(expected) in \(zone)")
    }
}
