import ChessCore
import SwiftUI

struct NewGameSetup: View {
    @Binding var settings: MatchSettings
    let replacesGame: Bool
    let onCancel: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Game").font(.headline)
            GameSetupFields(settings: $settings)
            if replacesGame {
                Text("Starting a new game replaces your current game. This cannot be undone.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button(replacesGame ? "Replace Game" : "Start Game", action: onStart)
            }
        }
        .controlSize(.small)
        .padding(16)
        .frame(width: 300)
    }
}

struct GameSetupFields: View {
    @Binding var settings: MatchSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("Opponent") {
                Picker("Opponent", selection: $settings.opponent) {
                    Text("Computer").tag(MatchSettings.Opponent.computer)
                    Text("Two Players").tag(MatchSettings.Opponent.human)
                }
                .pickerStyle(.segmented)
            }

            Group {
                row("Level") {
                    Picker("Level", selection: $settings.strength) {
                        ForEach(Array(EngineStrength.levels), id: \.self) { level in
                            let strength = EngineStrength(level: level)
                            Text(Self.label(for: strength)).tag(strength)
                        }
                    }
                }
                row("Play as") {
                    Picker("Play as", selection: $settings.colorChoice) {
                        Text("White").tag(MatchSettings.ColorChoice.white)
                        Text("Black").tag(MatchSettings.ColorChoice.black)
                        Text("Random").tag(MatchSettings.ColorChoice.random)
                    }
                    .pickerStyle(.segmented)
                }
                row("Time per move") {
                    Picker("Time per move", selection: $settings.moveTime) {
                        ForEach(MatchSettings.moveTimes, id: \.self) { seconds in
                            Text("\(seconds.formatted(.number.locale(Locale(identifier: "en_US")))) s").tag(seconds)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .disabled(settings.opponent != .computer)
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
