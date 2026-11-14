import SwiftUI

enum AppMode: String {
    case play, puzzle, online
}

/// Navigation stays separate from status text so neither competes for horizontal space.
struct PopoverHeader<Status: View>: View {
    @Binding var mode: AppMode
    @ViewBuilder let status: Status

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $mode) {
                Text("Play").tag(AppMode.play)
                Text("Puzzle").tag(AppMode.puzzle)
                Text("Online").tag(AppMode.online)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .frame(height: 22)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                status
            }
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
        }
    }
}

/// Ordinary messages wrap naturally; unusually long service errors remain scrollable.
struct StatusMessage: View {
    let text: String
    var isError = false

    var body: some View {
        ViewThatFits(in: .vertical) {
            label
            ScrollView {
                label
            }
            .scrollIndicators(.visible)
        }
        .frame(maxHeight: 96)
        .fixedSize(horizontal: false, vertical: true)
        .help(text)
    }

    private var label: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if isError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Error")
            }
            Text(text)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
