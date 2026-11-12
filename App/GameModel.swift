import AppKit
import ChessCore
import Observation

/// State of the popover: the game with its input state, the settings and the computer opponent.
@MainActor
@Observable
final class GameModel: BoardModel {
    private(set) var session: BoardSession
    /// `true` when black is at the bottom.
    var isFlipped: Bool
    /// The colour the human plays against the computer.
    private(set) var playerColor: PieceColor
    var settings: MatchSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    private(set) var isThinking = false
    /// Set when the engine could not be started or stopped answering.
    private(set) var engineFailed = false

    private let store: SavedGameStore
    private let defaults: UserDefaults
    private var engine: UCIEngine?
    private var engineStrength: EngineStrength?
    /// Identifies the latest search. Results of older searches are dropped.
    private var searchID = 0
    private var engineTask: Task<Void, Never>?

    private static let settingsKey = "matchSettings"

    init(store: SavedGameStore = GameModel.defaultStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults

        let settings = defaults.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(MatchSettings.self, from: $0) } ?? MatchSettings()
        self.settings = settings

        // A missing or unreadable save simply starts a fresh game.
        let saved = try? store.load()
        let playerColor = saved?.playerColor ?? settings.colorChoice.resolved()
        self.playerColor = playerColor
        session = BoardSession(
            game: (try? saved?.restoredGame()) ?? Game(),
            humanColors: settings.humanColors(playingAs: playerColor))
        isFlipped = settings.opponent == .computer && playerColor == .black

        requestEngineMoveIfNeeded()
    }

    static var defaultStore: SavedGameStore {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: Bundle.main.bundleIdentifier ?? "Knightbar")
        return SavedGameStore(fileURL: folder.appending(path: "game.json"))
    }

    var game: Game { session.game }
    var position: Position { session.game.position }
    var lastMove: Move? { session.game.lastMove }
    var selectedSquare: Square? { session.selectedSquare }
    var targetSquares: [Square] { session.targetSquares }
    var checkedKingSquare: Square? { session.checkedKingSquare }
    var hintSquares: [Square] { [] }
    var playsComputer: Bool { settings.opponent == .computer }

    // MARK: - Board input

    func canSelect(_ square: Square) -> Bool { session.canSelect(square) }
    func select(_ square: Square) { session.select(square) }
    func deselect() { session.deselect() }
    func cancelPromotion() { session.cancelPromotion() }

    func tap(_ square: Square) {
        session.tap(square)
        gameChanged()
    }

    func move(from: Square, to: Square) {
        session.move(from: from, to: to)
        gameChanged()
    }

    func promote(to kind: PieceKind) {
        session.promote(to: kind)
        gameChanged()
    }

    // MARK: - Game actions

    func undo() {
        cancelSearch()
        session.undo()
        gameChanged()
    }

    func resign() {
        cancelSearch()
        session.resign()
        gameChanged()
    }

    func newGame() {
        cancelSearch()
        playerColor = settings.colorChoice.resolved()
        session.newGame(humanColors: settings.humanColors(playingAs: playerColor))
        isFlipped = playsComputer && playerColor == .black
        gameChanged()
    }

    func retryEngine() {
        engineFailed = false
        requestEngineMoveIfNeeded()
    }

    func copyPGN() {
        let date = Date.now.formatted(.iso8601.year().month().day().dateSeparator(.omitted))
        let dotted = [date.prefix(4), date.dropFirst(4).prefix(2), date.suffix(2)].joined(separator: ".")
        var tags = ["Event": AppInfo.displayName, "Date": dotted]
        if playsComputer {
            let computer = "Stockfish level \(settings.strength.level)"
            tags["White"] = playerColor == .white ? "Player" : computer
            tags["Black"] = playerColor == .black ? "Player" : computer
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(game.pgn(tags: tags), forType: .string)
    }

    // MARK: - Settings and persistence

    private func settingsChanged(from old: MatchSettings) {
        guard settings != old else { return }
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.settingsKey)
        }
        // "Random" keeps the current colour; it is drawn again with the next new game.
        if settings.colorChoice != old.colorChoice, settings.colorChoice != .random {
            playerColor = settings.colorChoice.resolved()
        }
        let humanColors = settings.humanColors(playingAs: playerColor)
        if humanColors != session.humanColors {
            cancelSearch()
            session.humanColors = humanColors
            isFlipped = playsComputer && playerColor == .black
        }
        gameChanged()
    }

    private func gameChanged() {
        try? store.save(SavedGame(game: game, playerColor: playerColor))
        requestEngineMoveIfNeeded()
    }

    // MARK: - Computer opponent

    private func requestEngineMoveIfNeeded() {
        guard session.isEngineTurn, !isThinking, !engineFailed else { return }
        searchID += 1
        let id = searchID
        isThinking = true

        let game = session.game
        let strength = settings.strength
        let moveTime = Duration.milliseconds(Int(settings.moveTime * 1000))
        let previous = engineTask
        engineTask = Task {
            // The engine handles one request at a time, so wait for a cancelled search to wind down.
            await previous?.value
            guard id == searchID else { return }
            do {
                let engine = try await readyEngine(strength: strength)
                let move = try await engine.bestMove(from: game.startPosition, moves: game.moves, moveTime: moveTime)
                guard id == searchID else { return }
                isThinking = false
                session.playEngineMove(move)
                gameChanged()
            } catch {
                await discardEngine()
                guard id == searchID else { return }
                isThinking = false
                engineFailed = true
            }
        }
    }

    private func cancelSearch() {
        guard isThinking else { return }
        searchID += 1
        isThinking = false
        if let engine {
            Task { await engine.cancelSearch() }
        }
    }

    private func readyEngine(strength: EngineStrength) async throws -> UCIEngine {
        if engine == nil {
            guard let url = Bundle.main.url(forResource: "stockfish", withExtension: nil, subdirectory: "Stockfish") else {
                throw EngineError.terminated
            }
            let started = UCIEngine(transport: try ProcessTransport(executableURL: url))
            try await started.start()
            engine = started
            engineStrength = nil
        }
        if engineStrength != strength {
            try await engine!.setStrength(strength)
            engineStrength = strength
        }
        return engine!
    }

    private func discardEngine() async {
        let old = engine
        engine = nil
        engineStrength = nil
        await old?.shutdown()
    }

    // MARK: - Status line

    var statusText: String {
        func name(_ color: PieceColor) -> String { color == .white ? "White" : "Black" }
        switch game.status {
        case .ongoing:
            if engineFailed { return "Computer is unavailable" }
            if isThinking { return "Computer is thinking…" }
            let check = position.isInCheck ? " – check" : ""
            return (playsComputer ? "Your move" : "\(name(position.sideToMove)) to move") + check
        case .checkmate(let winner):
            if playsComputer { return winner == playerColor ? "Checkmate – you win" : "Checkmate – computer wins" }
            return "Checkmate – \(name(winner)) wins"
        case .resigned(let winner):
            if playsComputer { return "You resigned" }
            return "\(name(winner.opposite)) resigned – \(name(winner)) wins"
        case .stalemate:
            return "Draw – stalemate"
        case .draw(.fiftyMoves):
            return "Draw – fifty-move rule"
        case .draw(.threefoldRepetition):
            return "Draw – threefold repetition"
        case .draw(.insufficientMaterial):
            return "Draw – insufficient material"
        }
    }
}
