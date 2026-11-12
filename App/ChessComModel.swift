import AppKit
import ChessCore
import Observation

/// The Chess.com daily games in which the user is to move. They are only listed; moves are made on chess.com.
@MainActor
@Observable
final class ChessComModel {
    var username: String {
        didSet {
            guard username != oldValue else { return }
            defaults.set(username, forKey: Self.usernameKey)
            games = []
            message = nil
            lastCheck = nil
            hasLoaded = false
            refresh()
        }
    }
    private(set) var games: [ChessComGame] = []
    /// Why the games could not be loaded.
    private(set) var message: String?
    private(set) var isLoading = false

    private let client: ChessComClient
    private let defaults: UserDefaults
    private let notify: @MainActor (_ gameID: String) -> Void
    private var lastCheck: Date?
    private var hasLoaded = false
    private var pollTask: Task<Void, Never>?

    private static let usernameKey = "chessComUsername"
    private static let notifyKey = "lichessNotifyOnMove"

    init(client: ChessComClient = ChessComModel.defaultClient, defaults: UserDefaults = .standard,
         notify: @escaping @MainActor (String) -> Void = MoveNotifier.notifyChessComMove, pollInterval: Duration = .seconds(300)) {
        self.client = client
        self.defaults = defaults
        self.notify = notify
        username = defaults.string(forKey: Self.usernameKey) ?? ""
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: pollInterval)
            }
        }
    }

    static var defaultClient: ChessComClient {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return ChessComClient(userAgent: "\(AppInfo.displayName)/\(version)")
    }

    var hasUsername: Bool { !username.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Whether the menu bar icon should show its dot.
    var isMyTurnAnywhere: Bool { !games.isEmpty }

    /// Asks again unless the last answer is less than a minute old.
    func refreshIfDue() {
        if let lastCheck, Date.now.timeIntervalSince(lastCheck) < 60 { return }
        refresh()
    }

    func refresh() {
        guard hasUsername, !isLoading else { return }
        let username = username
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let latest = try await client.gamesToMove(for: username)
                guard username == self.username else { return }
                // Games that have appeared since the last check are new turns. The first answer is not news.
                let known = Set(games.map(\.id))
                if hasLoaded, defaults.bool(forKey: Self.notifyKey) {
                    for game in latest where !known.contains(game.id) { notify(game.id) }
                }
                games = latest
                message = nil
                hasLoaded = true
                lastCheck = .now
            } catch let error as ChessComError {
                guard username == self.username else { return }
                switch error {
                case .userNotFound:
                    games = []
                    message = "Chess.com knows no player named “\(username)”."
                case .offline:
                    message = "No connection to Chess.com."
                case .rateLimited:
                    message = "Chess.com asked for a pause. Trying again later."
                case .http(let status):
                    message = "Chess.com answered with an error (\(status))."
                case .invalidResponse:
                    message = "Chess.com sent an unexpected answer."
                }
            } catch {
                message = "Chess.com sent an unexpected answer."
            }
        }
    }

    func open(_ game: ChessComGame) {
        NSWorkspace.shared.open(game.url)
    }
}
