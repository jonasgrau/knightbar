import ChessCore
import SwiftUI

/// Settings for games and puzzles, laid over the board.
struct SettingsView: View {
    @Bindable var game: GameModel
    @Bindable var puzzles: PuzzleModel
    @Bindable var lichess: LichessModel
    let onDone: () -> Void

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

                HStack {
                    Toggle("Notify when it is my move", isOn: $lichess.notifiesOnMove)
                    Spacer()
                    Button("Done", action: onDone)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.small)
            .padding(14)
            .frame(width: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .shadow(radius: 8)
        }
        .onExitCommand(perform: onDone)
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
