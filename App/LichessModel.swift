import AppKit
import ChessCore
import Observation

/// State of the Lichess tab: login, the list of games and challenges, and the game that is open.
///
/// No engine is involved here. Moves go to Lichess and come back through the game stream.
@MainActor
@Observable
final class LichessModel: BoardModel {
    private(set) var account: LichessAccount?
    private(set) var isSigningIn = false
    private(set) var overview = LichessOverview()
    /// The list entry of the game that is open, set as soon as it is chosen.
    private(set) var openGameInfo: LichessGameInfo?
    /// The open game as the game stream reports it. `nil` until its first line has arrived.
    private(set) var openGame: LichessGame?
    private(set) var session: BoardSession?
    /// The latest problem to tell the user about.
    private(set) var message: String?
    var isFlipped = false
    var notifiesOnMove: Bool {
        didSet {
            guard notifiesOnMove != oldValue else { return }
            defaults.set(notifiesOnMove, forKey: Self.notifyKey)
            if notifiesOnMove {
                Task { if await !requestNotificationPermission() { notifiesOnMove = false } }
            }
        }
    }

    private let client: LichessClient
    private let tokens: any TokenStore
    private let authenticator: any WebAuthenticator
    private let defaults: UserDefaults
    private let requestNotificationPermission: @Sendable () async -> Bool
    private let notify: @MainActor (_ opponent: String, _ gameID: String) -> Void
    private var eventsTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var gameTask: Task<Void, Never>?
    /// Number of moves on the board while the last one is on its way to Lichess. Until the game
    /// stream shows that many moves, the board stays as it is and takes no input.
    private var sentMoveCount: Int?
    private var isSendingMove: Bool { sentMoveCount != nil }

    private static let notifyKey = "lichessNotifyOnMove"
    private static let accountKey = "lichessAccount"

    init(client: LichessClient = LichessModel.defaultClient,
         tokens: any TokenStore = KeychainTokenStore(),
         authenticator: any WebAuthenticator = SystemWebAuthenticator(),
         defaults: UserDefaults = .standard,
         requestNotificationPermission: @escaping @Sendable () async -> Bool = MoveNotifier.requestPermission,
         notify: @escaping @MainActor (String, String) -> Void = MoveNotifier.notifyYourMove) {
        self.client = client
        self.tokens = tokens
        self.authenticator = authenticator
        self.defaults = defaults
        self.requestNotificationPermission = requestNotificationPermission
        self.notify = notify
        notifiesOnMove = defaults.bool(forKey: Self.notifyKey)

        // With a stored token the user stays logged in across launches.
        if let token = tokens.load() {
            account = defaults.data(forKey: Self.accountKey)
                .flatMap { try? JSONDecoder().decode(LichessAccount.self, from: $0) }
            Task {
                await client.setToken(token)
                await loadAccountAndConnect()
            }
        }
    }

    static var defaultClient: LichessClient {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return LichessClient(userAgent: "\(AppInfo.displayName)/\(version)")
    }

    /// Whether the menu bar icon should show its dot.
    var isMyTurnAnywhere: Bool { account != nil && overview.isMyTurnAnywhere }

    /// Number of games played here in which the user is to move.
    var waitingGameCount: Int {
        account == nil ? 0 : overview.games.filter { $0.isPlayableHere && $0.isMyTurn }.count
    }

    // MARK: - Login

    func signIn() {
        guard !isSigningIn else { return }
        isSigningIn = true
        message = nil
        // Lichess needs no registration: the bundle identifier serves as client id and as the
        // URL scheme of the redirect.
        let identifier = (Bundle.main.bundleIdentifier ?? "knightbar").lowercased()
        let request = OAuthRequest(clientID: identifier, redirectURI: "\(identifier)://oauth", scopes: ["board:play"])
        Task {
            defer { isSigningIn = false }
            do {
                let callback = try await authenticator.authenticate(at: request.authorizationURL, callbackScheme: identifier)
                let code = try request.authorizationCode(fromCallback: callback)
                let token = try await client.exchangeCode(code, for: request)
                tokens.save(token)
                await client.setToken(token)
                await loadAccountAndConnect()
            } catch is CancellationError {
                // The user closed the login page.
            } catch let error as NSError where error.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" && error.code == 1 {
                // The user cancelled the login.
            } catch OAuthError.denied {
                message = "Lichess did not grant access."
            } catch {
                message = "Login failed. \(Self.text(for: error))"
            }
        }
    }

    func signOut() {
        let client = client
        Task {
            try? await client.revokeToken()
            await client.setToken(nil)
        }
        forgetLogin()
    }

    /// Drops everything that belongs to the login, on this Mac only.
    private func forgetLogin() {
        eventsTask?.cancel()
        pollTask?.cancel()
        closeGame()
        tokens.delete()
        defaults.removeObject(forKey: Self.accountKey)
        account = nil
        overview = LichessOverview()
    }

    private func loadAccountAndConnect() async {
        do {
            let account = try await client.account()
            self.account = account
            if let data = try? JSONEncoder().encode(account) { defaults.set(data, forKey: Self.accountKey) }
        } catch LichessError.unauthorized {
            forgetLogin()
            message = "Your Lichess login has expired. Please log in again."
            return
        } catch {
            // Offline at launch: keep the remembered account and let the streams retry.
            guard account != nil else {
                message = Self.text(for: error)
                return
            }
        }
        connect()
    }

    private func connect() {
        eventsTask?.cancel()
        pollTask?.cancel()
        eventsTask = Task { await runEventStream() }
        pollTask = Task {
            // The event stream reports games starting and ending, but not whose turn it is.
            while !Task.isCancelled {
                await refreshGames()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // MARK: - Streams

    /// Runs `body` again and again with growing pauses, until it returns `false` or the task is cancelled.
    private func repeatedly(_ body: () async throws -> Bool) async {
        var pause = Duration.seconds(2)
        while !Task.isCancelled {
            do {
                if try await !body() { return }
                pause = .seconds(2)
            } catch LichessError.unauthorized {
                forgetLogin()
                message = "Your Lichess login has expired. Please log in again."
                return
            } catch LichessError.rateLimited(let until) {
                try? await Task.sleep(for: .seconds(max(until.timeIntervalSinceNow, 1)))
                continue
            } catch {
                // Connection problems: try again after the pause.
            }
            try? await Task.sleep(for: pause)
            pause = min(pause * 2, .seconds(60))
        }
    }

    private func runEventStream() async {
        await repeatedly {
            for try await event in try await client.events() {
                guard let account else { return false }
                updateOverview { $0.apply(event, userID: account.id) }
            }
            return true
        }
    }

    func refreshGames() async {
        guard account != nil else { return }
        do {
            let games = try await client.ongoingGames()
            updateOverview { $0.replaceGames(games) }
        } catch LichessError.unauthorized {
            forgetLogin()
            message = "Your Lichess login has expired. Please log in again."
        } catch {
            // The next poll tries again.
        }
    }

    /// Changes the overview and notifies about games in which the opponent has just moved.
    private func updateOverview(_ change: (inout LichessOverview) -> Void) {
        let wasMyTurn = Dictionary(overview.games.map { ($0.id, $0.isMyTurn) }, uniquingKeysWith: { first, _ in first })
        change(&overview)
        guard notifiesOnMove else { return }
        // Only a game that was known to be waiting for the opponent counts. Games that show up
        // for the first time, for example at launch, do not trigger a notification.
        for game in overview.games where game.isPlayableHere && game.isMyTurn && wasMyTurn[game.id] == false {
            notify(game.opponentName, game.id)
        }
    }

    // MARK: - Open game

    func open(_ game: LichessGameInfo) {
        guard game.isPlayableHere else {
            NSWorkspace.shared.open(game.url)
            return
        }
        closeGame()
        message = nil
        openGameInfo = game
        isFlipped = game.color == .black
        gameTask = Task { await runGameStream(id: game.id) }
    }

    func closeGame() {
        gameTask?.cancel()
        gameTask = nil
        openGameInfo = nil
        openGame = nil
        session = nil
        sentMoveCount = nil
    }

    private func runGameStream(id: String) async {
        await repeatedly {
            for try await event in try await client.gameEvents(game: id) {
                guard let account, openGameInfo?.id == id else { return false }
                switch event {
                case .full(let full):
                    openGame = try LichessGame(full: full, userID: account.id)
                case .state(let state):
                    try openGame?.apply(state)
                case .other:
                    continue
                }
                showServerState()
            }
            // Lichess closes the stream when the game is over.
            return openGame?.result == nil
        }
    }

    /// Puts the position Lichess reports on the board.
    private func showServerState() {
        guard let game = openGame else { return }
        // While a move is on its way, the board is already one move ahead of Lichess.
        if let sentMoveCount {
            guard game.game.moves.count >= sentMoveCount || game.result != nil else { return }
            self.sentMoveCount = nil
        }
        updateOverview { $0.setMyTurn(game.isMyTurn, inGame: game.id) }
        if session?.game.moves != game.game.moves || session?.humanColors != humanColors(in: game) {
            session = BoardSession(game: game.game, humanColors: humanColors(in: game))
        }
    }

    private func humanColors(in game: LichessGame) -> Set<PieceColor> {
        game.result == nil ? [game.myColor] : []
    }

    // MARK: - Board

    var position: Position {
        session?.game.position ?? openGameInfo.flatMap { try? Position(fen: $0.fen) } ?? .start
    }
    var lastMove: Move? { session.map { $0.game.lastMove } ?? openGameInfo?.lastMove }
    var selectedSquare: Square? { session?.selectedSquare }
    var targetSquares: [Square] { session?.targetSquares ?? [] }
    var checkedKingSquare: Square? { session?.checkedKingSquare }
    var hintSquares: [Square] { [] }

    func canSelect(_ square: Square) -> Bool { !isSendingMove && session?.canSelect(square) ?? false }
    func select(_ square: Square) { if !isSendingMove { session?.select(square) } }
    func deselect() { session?.deselect() }
    func cancelPromotion() { session?.cancelPromotion() }

    func tap(_ square: Square) {
        guard !isSendingMove else { return }
        session?.tap(square)
        sendMoveIfMade()
    }

    func move(from: Square, to: Square) {
        guard !isSendingMove else { return }
        session?.move(from: from, to: to)
        sendMoveIfMade()
    }

    func promote(to kind: PieceKind) {
        guard !isSendingMove else { return }
        session?.promote(to: kind)
        sendMoveIfMade()
    }

    /// Sends the move the user just made on the board to Lichess and takes it back if Lichess refuses.
    private func sendMoveIfMade() {
        guard let session, let game = openGame, session.game.moves.count == game.game.moves.count + 1,
              let move = session.game.moves.last
        else { return }
        sentMoveCount = session.game.moves.count
        message = nil
        updateOverview { $0.setMyTurn(false, inGame: game.id) }
        Task {
            do {
                try await client.move(move, inGame: game.id)
            } catch {
                guard openGame?.id == game.id else { return }
                message = "The move was not sent. \(Self.text(for: error))"
                // Back to what Lichess knows.
                sentMoveCount = nil
                self.session = nil
                showServerState()
            }
        }
    }

    // MARK: - Game and challenge actions

    func resign() {
        guard let id = openGame?.id else { return }
        run { try await $0.resign(game: id) }
    }

    /// Offers a draw, or accepts the opponent's offer.
    func offerOrAcceptDraw() {
        guard let id = openGame?.id else { return }
        run { try await $0.answerDraw(true, inGame: id) }
    }

    func declineDraw() {
        guard let id = openGame?.id else { return }
        run { try await $0.answerDraw(false, inGame: id) }
    }

    func accept(_ challenge: LichessChallenge) {
        run { try await $0.acceptChallenge(challenge.id) }
    }

    func decline(_ challenge: LichessChallenge) {
        overview.removeChallenge(id: challenge.id)
        run { try await $0.declineChallenge(challenge.id) }
    }

    /// Challenges `username` to an unrated correspondence game.
    func challenge(username: String, daysPerMove: Int, color: PieceColor?) {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        run { try await $0.challenge(user: name, daysPerMove: daysPerMove, color: color) }
    }

    func openInBrowser() {
        guard let url = openGame?.url ?? openGameInfo?.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func run(_ action: @escaping @Sendable (LichessClient) async throws -> Void) {
        message = nil
        let client = client
        Task {
            do {
                try await action(client)
            } catch LichessError.unauthorized {
                forgetLogin()
                message = "Your Lichess login has expired. Please log in again."
            } catch {
                message = Self.text(for: error)
            }
        }
    }

    private static func text(for error: any Error) -> String {
        switch error {
        case LichessError.offline: "No connection to Lichess."
        case LichessError.rateLimited: "Lichess asked for a pause. Please try again in a minute."
        case LichessError.http(_, let text?): text
        case LichessError.http(let status, nil): "Lichess answered with an error (\(status))."
        case LichessError.unauthorized: "Please log in again."
        default: "Lichess sent an unexpected answer."
        }
    }

    // MARK: - Status line

    var statusText: String {
        if let message { return message }
        guard let account else { return isSigningIn ? "Waiting for Lichess…" : "Lichess" }
        guard let info = openGameInfo else {
            let waiting = waitingGameCount
            return waiting == 0 ? account.username : "Your move in \(waiting) game\(waiting == 1 ? "" : "s")"
        }
        guard let game = openGame else { return "Loading game…" }
        switch game.result {
        case .won(let color):
            return "\(game.resultReason ?? "Game over") – you \(color == game.myColor ? "won" : "lost")"
        case .draw:
            return game.resultReason == "Draw" ? "Draw" : "Draw – \(game.resultReason?.lowercased() ?? "game over")"
        case .aborted:
            return "Game aborted"
        case nil:
            if game.opponentOffersDraw { return "\(info.opponentName) offers a draw" }
            let check = game.game.position.isInCheck ? " – check" : ""
            return (game.isMyTurn ? "Your move" : "Waiting for \(info.opponentName)") + check
        }
    }
}
