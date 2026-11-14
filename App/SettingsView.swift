import ChessCore
import ServiceManagement
import SwiftUI

/// App and puzzle preferences; match setup lives under New Game.
struct SettingsView: View {
    @Bindable var puzzles: PuzzleModel
    @Bindable var lichess: LichessModel
    @Bindable var updates: UpdateModel
    let onDone: () -> Void
    /// Read from the system each time Settings opens, because it can also be changed in System Settings.
    @State private var loginState = LaunchAtLogin().state
    @State private var loginError: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.35)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDone)
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            settingsSection("Puzzle") { puzzleSettings }
                            Divider()
                            settingsSection("App") { appSettings }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Divider()
                    HStack {
                        Spacer()
                        Button("Done", action: onDone)
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .controlSize(.small)
                // Leave room around the card and keep dismissal outside the scrolling content.
                .frame(width: min(280, max(0, geometry.size.width - 16)),
                       height: max(0, geometry.size.height - 16))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onExitCommand(perform: onDone)
        .onAppear { loginState = LaunchAtLogin().state }
    }

    private var puzzleSettings: some View {
        row("Daily puzzle from") {
            Picker("Daily puzzle from", selection: $puzzles.source) {
                Text("Lichess").tag(Puzzle.Source.lichess)
                Text("Chess.com").tag(Puzzle.Source.chessCom)
            }
            .pickerStyle(.segmented)
        }
    }

    private var appSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            Toggle("Notify when it is my move", isOn: $lichess.notifiesOnMove)
            Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
            updateLine
            HStack(spacing: 6) {
                Text("Version \(updates.currentVersion?.description ?? "?")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Check Now", action: updates.checkNow)
                    .disabled(updates.isChecking)
                if updates.isChecking {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.6)
                }
            }
        }
    }

    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    /// What the last check found: a newer version with the way to get it, or the result of "Check Now".
    @ViewBuilder
    private var updateLine: some View {
        if let available = updates.available {
            HStack(spacing: 4) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                if let command = updates.upgradeCommand {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Version \(available.version.description) is out. Update with:")
                        Text(command)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                } else {
                    Text("Version \(available.version.description) is available.")
                    Button("Download", action: updates.openReleasePage)
                }
            }
            .font(.caption)
            .fixedSize(horizontal: false, vertical: true)
        } else if let message = updates.message {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                loginError = "macOS did not accept this. Is \(AppInfo.displayName) in the Applications folder?"
            }
        }
    }

    private var loginNote: String? {
        if let loginError { return loginError }
        switch loginState {
        case .needsApproval: return "Allow \(AppInfo.displayName) under Login Items in System Settings."
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

}
