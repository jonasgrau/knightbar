import SwiftUI

@main
struct KnightbarApp: App {
    @State private var game = GameModel()
    @State private var puzzles = PuzzleModel()
    @State private var lichess = LichessModel()
    @State private var chessCom = ChessComModel()
    @State private var updates = UpdateModel()

    /// Whether the user is to move in a Lichess or Chess.com game.
    private var isMyTurnAnywhere: Bool { lichess.isMyTurnAnywhere || chessCom.isMyTurnAnywhere }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(game: game, puzzles: puzzles, lichess: lichess, chessCom: chessCom, updates: updates)
        } label: {
            Image(nsImage: MenuBarIcon.image(showsDot: isMyTurnAnywhere))
                .accessibilityLabel(isMyTurnAnywhere ? "\(AppInfo.displayName), your move" : AppInfo.displayName)
        }
        .menuBarExtraStyle(.window)
    }
}
