import SwiftUI

/// Content of the popover: mode switch, full-width status, board and toolbar.
struct PopoverView: View {
    let game: GameModel
    let puzzles: PuzzleModel
    let lichess: LichessModel
    let chessCom: ChessComModel
    let updates: UpdateModel
    @AppStorage("mode") private var mode = AppMode.play
    @State private var showsSettings = false

    var body: some View {
        VStack(spacing: 8) {
            PopoverHeader(mode: $mode) {
                switch mode {
                case .play: GameStatus(model: game)
                case .puzzle: PuzzleStatus(model: puzzles)
                case .online: OnlineStatus(lichess: lichess, chessCom: chessCom)
                }
            }

            Group {
                switch mode {
                case .play: GameBoard(model: game)
                case .puzzle: PuzzleBoard(model: puzzles)
                case .online: OnlineBoard(lichess: lichess, chessCom: chessCom)
                }
            }
            .frame(width: 320, height: 320)
            .overlay {
                if showsSettings {
                    SettingsView(puzzles: puzzles, lichess: lichess, updates: updates) { showsSettings = false }
                }
            }

            HStack(spacing: 4) {
                switch mode {
                case .play: GameToolbar(model: game)
                case .puzzle: PuzzleToolbar(model: puzzles)
                case .online: OnlineToolbar(lichess: lichess, chessCom: chessCom)
                }
                Spacer()
                Menu {
                    Button(updates.available == nil ? "Settings…" : "Settings… – update available") {
                        showsSettings.toggle()
                    }
                    Divider()
                    Button("Quit \(AppInfo.displayName)") {
                        NSApplication.shared.terminate(nil)
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 16)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(updates.available == nil ? "App menu" : "App menu – update available")
                .accessibilityLabel("App menu")
                .overlay(alignment: .topTrailing) {
                    if updates.available != nil {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 7, height: 7)
                            .offset(x: 2, y: -2)
                            .allowsHitTesting(false)
                    }
                }
            }
            .controlSize(.small)
            .frame(height: 22)
        }
        .padding(10)
        .frame(width: 340)
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
