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
    var setup = model.settings
    setup.opponent = .human
    setup.strength = EngineStrength(level: 5)
    model.startNewGame(settings: setup)
    try requireRegression(model.settings == setup && !model.playsComputer,
                          "New Game did not apply the selected opponent and strength")
    try requireRegression(!model.replacesGameInProgress && model.game.moves.isEmpty,
                          "An untouched game should not ask before it is replaced")
    model.move(from: Square("e2")!, to: Square("e4")!)
    let moves = model.game.moves
    try requireRegression(model.replacesGameInProgress,
                          "A game in progress should warn before New Game replaces it")

    // A restored game receives the same protection as one played in this session.
    let restored = GameModel(store: store, defaults: defaults)
    try requireRegression(restored.replacesGameInProgress && restored.game.moves == moves,
                          "Restored progress was not protected")

    model.resign()
    try requireRegression(!model.replacesGameInProgress,
                          "A finished game should not ask before it is replaced")
    model.newGame()
    try requireRegression(model.game.moves.isEmpty, "New Game did not reset the session")
    try requireRegression(try store.load()?.moves.isEmpty == true, "The new game was not saved")
    model.move(from: Square("e2")!, to: Square("e4")!)
    setup.strength = EngineStrength(level: 8)
    setup.colorChoice = .black
    model.startNewGame(settings: setup)
    try requireRegression(model.game.moves.isEmpty && model.settings == setup && model.playerColor == .black,
                          "Starting with a new setup did not replace the active game and apply its choices")
    let restarted = GameModel(store: store, defaults: defaults)
    try requireRegression(restarted.settings == setup && restarted.playerColor == .black && restarted.game.moves.isEmpty,
                          "New-game setup was not retained after restoring")
    print("PASS: fresh, active, restored, finished and configured New Game flows")
}
