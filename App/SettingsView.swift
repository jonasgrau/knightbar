import ChessCore
import ServiceManagement
import SwiftUI

/// Settings for games and puzzles, laid over the board.
struct SettingsView: View {
    @Bindable var game: GameModel
    @Bindable var puzzles: PuzzleModel
    @Bindable var lichess: LichessModel
    let onDone: () -> Void
    /// Read from the system each time Settings opens, because it can also be changed in System Settings.
    @State private var loginState = LaunchAtLogin().state
    @State private var loginError: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDone)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                row("Opponent") {
                    Picker("Opponent", selection: $game.settings.opponent) {
                        Text("Computer").tag(MatchSettings.Opponent.computer)
                        Text("Two Players").tag(MatchSettings.Opponent.human)
                    }
                    .pickerStyle(.segmented)
                }

                Group {
                    row("Level") {
                        Picker("Level", selection: $game.settings.strength) {
                            ForEach(Array(EngineStrength.levels), id: \.self) { level in
                                let strength = EngineStrength(level: level)
                                Text(Self.label(for: strength)).tag(strength)
                            }
                        }
                    }
                    row("Play as") {
                        Picker("Play as", selection: $game.settings.colorChoice) {
                            Text("White").tag(MatchSettings.ColorChoice.white)
                            Text("Black").tag(MatchSettings.ColorChoice.black)
                            Text("Random").tag(MatchSettings.ColorChoice.random)
                        }
                        .pickerStyle(.segmented)
                    }
                    row("Time per move") {
                        Picker("Time per move", selection: $game.settings.moveTime) {
                            ForEach(MatchSettings.moveTimes, id: \.self) { seconds in
                                Text("\(seconds.formatted(.number.locale(Locale(identifier: "en_US")))) s").tag(seconds)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .disabled(!game.playsComputer)

                row("Daily puzzle from") {
                    Picker("Daily puzzle from", selection: $puzzles.source) {
                        Text("Lichess").tag(Puzzle.Source.lichess)
                        Text("Chess.com").tag(Puzzle.Source.chessCom)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Open at login", isOn: launchAtLoginBinding)
                    if let note = loginNote {
                        HStack(spacing: 4) {
                            Text(note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if loginState == .needsApproval {
                                Button("Open") { SMAppService.openSystemSettingsLoginItems() }
                            }
                        }
                    }
                    HStack {
                        Toggle("Notify when it is my move", isOn: $lichess.notifiesOnMove)
                        Spacer()
                        Button("Done", action: onDone)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .controlSize(.small)
            .padding(14)
            .frame(width: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 8)
        }
        .onExitCommand(perform: onDone)
        .onAppear { loginState = LaunchAtLogin().state }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding {
            loginState == .on || loginState == .needsApproval
        } set: { enabled in
            do {
                loginState = try LaunchAtLogin().setEnabled(enabled)
                loginError = nil
            } catch {
                loginState = LaunchAtLogin().state
                loginError = "macOS did not accept this. Is Knightbar in the Applications folder?"
            }
        }
    }

    private var loginNote: String? {
        if let loginError { return loginError }
        switch loginState {
        case .needsApproval: return "Allow Knightbar under Login Items in System Settings."
        case .on, .off: return nil
        }
    }

    private func row(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            content()
                .labelsHidden()
        }
    }

    static func label(for strength: EngineStrength) -> String {
        if let elo = strength.elo {
            "Level \(strength.level) – about \(elo) Elo"
        } else {
            "Level \(strength.level) – full strength"
        }
    }
}
