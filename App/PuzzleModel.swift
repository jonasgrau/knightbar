import AppKit
import ChessCore
import Observation

/// State of the puzzle tab: the daily puzzle of the chosen source and the attempt to solve it.
@MainActor
@Observable
final class PuzzleModel: BoardModel {
    private(set) var session: PuzzleSession?
    private(set) var isLoading = false
    /// Why the puzzle could not be loaded. Only shown while there is no puzzle to display.
    private(set) var loadError: String?
    var isFlipped = false
    var source: Puzzle.Source {
        didSet {
            guard source != oldValue else { return }
            defaults.set(source.rawValue, forKey: Self.sourceKey)
            session = nil
            loadError = nil
            refreshIfNeeded()
        }
    }

    private var solved: SolvedPuzzles
    private let client: PuzzleClient
    private let cache: PuzzleCache
    private let defaults: UserDefaults
    private var replyTask: Task<Void, Never>?

    private static let sourceKey = "puzzleSource"
    private static let solvedKey = "solvedPuzzles"

    init(client: PuzzleClient = PuzzleModel.defaultClient, cache: PuzzleCache = PuzzleModel.defaultCache,
         defaults: UserDefaults = .standard) {
        self.client = client
        self.cache = cache
        self.defaults = defaults
        source = defaults.string(forKey: Self.sourceKey).flatMap(Puzzle.Source.init(rawValue:)) ?? .lichess
        solved = defaults.data(forKey: Self.solvedKey)
            .flatMap { try? JSONDecoder().decode(SolvedPuzzles.self, from: $0) } ?? SolvedPuzzles()
    }

    static var defaultClient: PuzzleClient {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return PuzzleClient(userAgent: "\(AppInfo.displayName)/\(version)")
    }

    static var defaultCache: PuzzleCache {
        let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.main.bundleIdentifier ?? "Knightbar")
        return PuzzleCache(folder: folder)
    }

    // MARK: - Loading

    /// Shows the stored puzzle right away and fetches a new one if the stored one is older than 15 minutes.
    func refreshIfNeeded() {
        let source = source
        let entry = cache.entry(for: source)
        if session == nil, let entry, let puzzle = try? Puzzle(source: source, data: entry.data) {
            show(puzzle)
        }
        guard !isLoading, entry?.isFresh(at: .now) != true else { return }

        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let data = try await client.dailyPuzzleData(from: source)
                let puzzle = try Puzzle(source: source, data: data)
                try? cache.store(data, for: source, fetchedAt: .now)
                guard source == self.source else { return }
                loadError = nil
                // Keep the attempt in progress if the puzzle of the day has not changed.
                if session?.puzzle.id != puzzle.id { show(puzzle) }
            } catch {
                guard source == self.source else { return }
                loadError = Self.message(for: error)
            }
        }
    }

    private func show(_ puzzle: Puzzle) {
        replyTask?.cancel()
        session = PuzzleSession(puzzle: puzzle)
        isFlipped = puzzle.solverColor == .black
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case PuzzleClientError.offline:
            "No connection to the puzzle service."
        case PuzzleClientError.rateLimited:
            "Too many requests. Please try again in a minute."
        case PuzzleClientError.http(let status):
            "The puzzle service answered with an error (\(status))."
        default:
            "Today's puzzle could not be read."
        }
    }

    // MARK: - Board

    var position: Position { session?.position ?? .start }
    var lastMove: Move? { session?.lastMove }
    var selectedSquare: Square? { session?.selectedSquare }
    var targetSquares: [Square] { session?.targetSquares ?? [] }
    var checkedKingSquare: Square? { session?.checkedKingSquare }

    var hintSquares: [Square] {
        switch session?.hint {
        case .piece(let square): [square]
        case .move(let move): [move.from, move.to]
        case nil: []
        }
    }

    func canSelect(_ square: Square) -> Bool { session?.canSelect(square) ?? false }
    func select(_ square: Square) { session?.select(square) }
    func deselect() { session?.deselect() }
    func cancelPromotion() { session?.cancelPromotion() }

    func tap(_ square: Square) {
        session?.tap(square)
        attemptFinished()
    }

    func move(from: Square, to: Square) {
        session?.move(from: from, to: to)
        attemptFinished()
    }

    func promote(to kind: PieceKind) {
        session?.promote(to: kind)
        attemptFinished()
    }

    /// After a correct move: lets the opponent answer after a short pause, or records the solution.
    private func attemptFinished() {
        guard let session else { return }
        switch session.state {
        case .awaitingReply:
            guard replyTask == nil else { return }
            replyTask = Task {
                try? await Task.sleep(for: .milliseconds(450))
                replyTask = nil
                guard !Task.isCancelled else { return }
                self.session?.playReply()
            }
        case .solved:
            guard !solved.contains(session.puzzle) else { return }
            solved.insert(session.puzzle)
            if let data = try? JSONEncoder().encode(solved) {
                defaults.set(data, forKey: Self.solvedKey)
            }
        case .solving:
            break
        }
    }

    // MARK: - Actions

    func showHint() { session?.showHint() }

    func startOver() {
        replyTask?.cancel()
        replyTask = nil
        session?.restart()
    }

    func openInBrowser() {
        guard let url = session?.puzzle.url else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Status line

    /// Whether the shown puzzle was solved in an earlier attempt.
    var wasSolvedBefore: Bool {
        session.map { solved.contains($0.puzzle) } ?? false
    }

    var statusText: String {
        guard let session else { return isLoading ? "Loading puzzle…" : "Daily Puzzle" }
        switch session.state {
        case .solved:
            return "Solved"
        case .awaitingReply:
            return "Correct"
        case .solving:
            if session.lastAttemptFailed { return "Not the move – try again" }
            let side = session.puzzle.solverColor == .white ? "White" : "Black"
            return wasSolvedBefore ? "\(side) to move – solved before" : "\(side) to move"
        }
    }
}
