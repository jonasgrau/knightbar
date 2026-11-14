import ChessCore
import Foundation

@MainActor
func newGameSafetyRegressions() throws {
    let suite = "Knightbar.NewGameSafety.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    let folder = FileManager.default.temporaryDirectory.appending(path: suite)
    let store = SavedGameStore(fileURL: folder.appending(path: "game.json"))
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }
    let model = GameModel(store: store, defaults: defaults)
    model.settings.opponent = .human
    model.requestNewGame()
    try requireRegression(!model.confirmsNewGame && model.game.moves.isEmpty,
                          "An untouched game should restart immediately")
    model.move(from: Square("e2")!, to: Square("e4")!)
    let moves = model.game.moves
    let saved = try Data(contentsOf: store.fileURL)
    model.requestNewGame()
    try requireRegression(model.confirmsNewGame && model.game.moves == moves,
                          "Requesting a new game replaced active progress before confirmation")
    try requireRegression(try Data(contentsOf: store.fileURL) == saved,
                          "Requesting a new game overwrote the save")
    model.confirmsNewGame = false
    try requireRegression(model.game.moves == moves && (try Data(contentsOf: store.fileURL)) == saved,
                          "Cancelling New Game changed the board or save")

    // A restored game receives the same protection as one played in this session.
    let restored = GameModel(store: store, defaults: defaults)
    restored.requestNewGame()
    try requireRegression(restored.confirmsNewGame && restored.game.moves == moves,
                          "Restored progress was replaced before confirmation")

    model.requestNewGame()
    model.newGame()
    try requireRegression(!model.confirmsNewGame && model.game.moves.isEmpty,
                          "Confirmed New Game did not reset the session")
    try requireRegression(try store.load()?.moves.isEmpty == true, "Confirmed game was not saved")
    model.move(from: Square("e2")!, to: Square("e4")!)
    model.resign()
    model.requestNewGame()
    try requireRegression(!model.confirmsNewGame && model.game.moves.isEmpty,
                          "A finished game should restart immediately")
    print("PASS: fresh, active, cancelled, restored, confirmed, and finished New Game flows")
}
