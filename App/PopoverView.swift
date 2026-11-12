import SwiftUI

enum AppMode: String {
    case play, puzzle, online
}

/// Content of the popover: status line with the mode switch, board and toolbar.
struct PopoverView: View {
    let game: GameModel
    let puzzles: PuzzleModel
    let lichess: LichessModel
    let chessCom: ChessComModel
    @AppStorage("mode") private var mode = AppMode.play
    @State private var showsSettings = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                switch mode {
                case .play: GameStatus(model: game)
                case .puzzle: PuzzleStatus(model: puzzles)
                case .online: OnlineStatus(lichess: lichess, chessCom: chessCom)
                }
                Spacer(minLength: 4)
                Picker("Mode", selection: $mode) {
                    Text("Play").tag(AppMode.play)
                    Text("Puzzle").tag(AppMode.puzzle)
                    Text("Online").tag(AppMode.online)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .controlSize(.small)
            }
            .frame(height: 22)

            Group {
                switch mode {
                case .play: GameBoard(model: game)
                case .puzzle: PuzzleBoard(model: puzzles)
                case .online: OnlineBoard(lichess: lichess, chessCom: chessCom)
                }
            }
            .overlay {
                if showsSettings {
                    SettingsView(game: game, puzzles: puzzles, lichess: lichess) { showsSettings = false }
                }
            }

            HStack(spacing: 4) {
                switch mode {
                case .play: GameToolbar(model: game)
                case .puzzle: PuzzleToolbar(model: puzzles)
                case .online: OnlineToolbar(lichess: lichess, chessCom: chessCom)
                }
                Spacer()
                ToolButton("Settings", symbol: "gearshape") { showsSettings.toggle() }
                ToolButton("Quit \(AppInfo.displayName)", symbol: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .controlSize(.small)
            .frame(height: 22)
        }
        .padding(10)
        .frame(width: 340, height: 400)
        .task(id: mode) {
            if mode == .puzzle { puzzles.refreshIfNeeded() }
        }
        // The popover's content stays alive while it is closed, so refresh whenever it opens again.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            if mode == .puzzle { puzzles.refreshIfNeeded() }
            chessCom.refreshIfDue()
        }
    }
}

/// An icon button for the toolbar. The title is its tooltip and accessibility label.
struct ToolButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    init(_ title: String, symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 16)
        }
        .help(title)
        .accessibilityLabel(title)
    }
}
