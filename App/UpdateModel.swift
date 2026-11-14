import AppKit
import ChessCore
import Observation

/// Looks for a newer Knightbar release on GitHub, automatically once a day or when asked.
/// It only tells the user; the download happens on the release page or through Homebrew.
@MainActor
@Observable
final class UpdateModel {
    var checksAutomatically: Bool {
        didSet {
            guard checksAutomatically != oldValue else { return }
            defaults.set(checksAutomatically, forKey: Self.automaticKey)
            if checksAutomatically { checkIfDue() }
        }
    }
    /// A newer release, if one was found.
    private(set) var available: AvailableUpdate?
    private(set) var isChecking = false
    /// The outcome of a check the user started, e.g. "Knightbar is up to date."
    private(set) var message: String?

    let currentVersion: AppVersion?
    let installSource: InstallSource

    private let checker: UpdateChecker
    private let defaults: UserDefaults
    private var loop: Task<Void, Never>?

    static let cask = "knightbar"
    private static let automaticKey = "checksForUpdates"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let availableVersionKey = "availableUpdateVersion"
    private static let availableURLKey = "availableUpdateURL"

    init(checker: UpdateChecker = UpdateModel.defaultChecker, defaults: UserDefaults = .standard,
         currentVersion: AppVersion? = UpdateModel.bundleVersion, installSource: InstallSource = .detect(cask: UpdateModel.cask)) {
        self.checker = checker
        self.defaults = defaults
        self.currentVersion = currentVersion
        self.installSource = installSource
        checksAutomatically = defaults.object(forKey: Self.automaticKey) as? Bool ?? true

        // A release found earlier stays announced until this version catches up.
        if let text = defaults.string(forKey: Self.availableVersionKey), let version = AppVersion(text),
           let link = defaults.string(forKey: Self.availableURLKey), let url = URL(string: link),
           let currentVersion, version > currentVersion {
            available = AvailableUpdate(version: version, url: url)
        }

        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.checkIfDue()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    static var bundleVersion: AppVersion? {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String).flatMap(AppVersion.init)
    }

    static var defaultChecker: UpdateChecker {
        UpdateChecker(repository: "jonasgrau/knightbar",
                      userAgent: "\(AppInfo.displayName)/\(bundleVersion?.description ?? "0")")
    }

    /// The command for Homebrew installs, `nil` for downloads.
    var upgradeCommand: String? { installSource.upgradeCommand(cask: Self.cask) }

    func checkIfDue() {
        let lastCheck = defaults.object(forKey: Self.lastCheckKey) as? Date
        guard checksAutomatically, UpdateSchedule.isDue(lastCheck: lastCheck, now: .now) else { return }
        check(reportResult: false)
    }

    /// A check the user asked for: it always runs and reports its outcome.
    func checkNow() {
        check(reportResult: true)
    }

    func openReleasePage() {
        guard let available else { return }
        NSWorkspace.shared.open(available.url)
    }

    private func check(reportResult: Bool) {
        guard !isChecking, let currentVersion else { return }
        isChecking = true
        if reportResult { message = nil }
        Task {
            defer { isChecking = false }
            do {
                let update = try await checker.availableUpdate(current: currentVersion)
                defaults.set(Date.now, forKey: Self.lastCheckKey)
                available = update
                defaults.set(update?.version.description, forKey: Self.availableVersionKey)
                defaults.set(update?.url.absoluteString, forKey: Self.availableURLKey)
                if reportResult, update == nil { message = "\(AppInfo.displayName) is up to date." }
            } catch let error as UpdateCheckError {
                // Automatic checks fail silently and try again later.
                guard reportResult else { return }
                message = switch error {
                case .offline: "No connection to GitHub."
                case .rateLimited: "GitHub asked for a pause. Try again later."
                case .http, .invalidResponse: "GitHub sent an unexpected answer."
                }
            } catch {
                if reportResult { message = "GitHub sent an unexpected answer." }
            }
        }
    }
}
