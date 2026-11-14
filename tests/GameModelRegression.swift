import ChessCore
import Foundation

/// The standalone test executable has no bundled Stockfish, so engine startup fails deterministically.
@main
struct GameModelRegression {
    @MainActor
    static func main() async throws {
        for action in ["new game", "two players", "opponent switch"] {
            try await engineFailureRecovery(action: action)
        }
        print("GameModel engine failure regressions passed.")
    }

    @MainActor
    static func engineFailureRecovery(action: String) async throws {
        let suite = "Knightbar.GameModelRegression.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let folder = FileManager.default.temporaryDirectory.appending(path: suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let model = GameModel(store: SavedGameStore(fileURL: folder.appending(path: "game.json")),
                              defaults: defaults)
        model.move(from: Square("e2")!, to: Square("e4")!)
        try await waitForRegression("engine startup failure") { model.engineFailed && !model.isThinking }
        try requireRegression(model.statusText == "Computer is unavailable", "Missing engine error")
        switch action {
        case "new game":
            model.newGame()
            try requireRegression(!model.engineFailed && model.statusText == "Your move",
                                  "New game retained the engine failure")
            model.move(from: Square("e2")!, to: Square("e4")!)
            try requireRegression(model.isThinking, "New game did not retry the engine")
            try await waitForRegression("engine retry") { model.engineFailed && !model.isThinking }
        default:
            model.settings.opponent = .human
            try requireRegression(!model.engineFailed && model.statusText == "Black to move",
                                  "Two-player game retained the engine failure")
            if action == "opponent switch" {
                model.settings.opponent = .computer
                try requireRegression(model.isThinking && !model.engineFailed,
                                      "Switching back did not retry the engine")
                try await waitForRegression("engine after opponent switch") { model.engineFailed && !model.isThinking }
            }
        }
        print("PASS: engine failure recovery via \(action)")
    }
}
