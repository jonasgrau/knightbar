import Foundation

/// A Lichess game the user plays, kept up to date from its game stream.
///
/// Lichess decides how the game ends. The moves are only replayed here to show the board.
public struct LichessGame: Sendable {
    public enum Result: Hashable, Sendable {
        case won(PieceColor)
        case draw
        case aborted
    }

    public let id: String
    public let myColor: PieceColor
    public let opponentName: String
    public private(set) var game: Game
    /// `nil` while the game is in progress.
    public private(set) var result: Result?
    /// How the game ended, in words. `nil` while it is in progress.
    public private(set) var resultReason: String?
    public private(set) var opponentOffersDraw = false
    public private(set) var iOfferDraw = false

    private let startPosition: Position

    /// Throws if `userID` plays neither side or the game data is inconsistent.
    public init(full: LichessGameFull, userID: String) throws {
        let user = userID.lowercased()
        if full.whiteID?.lowercased() == user {
            myColor = .white
            opponentName = full.blackName
        } else if full.blackID?.lowercased() == user {
            myColor = .black
            opponentName = full.whiteName
        } else {
            throw LichessError.invalidResponse
        }
        id = full.id

        if full.initialFEN == "startpos" {
            startPosition = .start
        } else {
            guard let position = try? Position(fen: full.initialFEN) else { throw LichessError.invalidResponse }
            startPosition = position
        }
        game = Game(position: startPosition, automaticDraws: false)
        try apply(full.state)
    }

    public var url: URL { URL(string: "https://lichess.org/\(id)")! }

    public var isMyTurn: Bool {
        result == nil && game.position.sideToMove == myColor
    }

    /// Takes over a new state from the game stream.
    public mutating func apply(_ state: LichessGameState) throws {
        var replayed = Game(position: startPosition, automaticDraws: false)
        for text in state.moves {
            guard let move = replayed.position.move(uci: text), replayed.make(move) else {
                throw LichessError.invalidResponse
            }
        }
        game = replayed

        opponentOffersDraw = myColor == .white ? state.blackOffersDraw : state.whiteOffersDraw
        iOfferDraw = myColor == .white ? state.whiteOffersDraw : state.blackOffersDraw

        switch state.status {
        case "created", "started":
            result = nil
            resultReason = nil
        case "aborted":
            result = .aborted
            resultReason = "Aborted"
        default:
            result = state.winner.map(Result.won) ?? .draw
            resultReason = Self.reasons[state.status] ?? "Game over"
        }
    }

    private static let reasons = [
        "mate": "Checkmate",
        "resign": "Resignation",
        "stalemate": "Stalemate",
        "timeout": "Opponent left",
        "draw": "Draw",
        "outoftime": "Time out",
        "cheat": "Cheat detected",
        "noStart": "Game not started",
        "insufficientMaterialClaim": "Draw",
    ]
}

/// The user's ongoing Lichess games and open challenges.
public struct LichessOverview: Sendable {
    private var unsortedGames: [LichessGameInfo] = []
    public private(set) var incomingChallenges: [LichessChallenge] = []
    public private(set) var outgoingChallenges: [LichessChallenge] = []

    public init() {}

    /// Correspondence games first, and within each group the games where the user is to move.
    public var games: [LichessGameInfo] {
        func rank(_ game: LichessGameInfo) -> Int {
            (game.isCorrespondence ? 0 : 2) + (game.isMyTurn ? 0 : 1)
        }
        return unsortedGames.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .map(\.element)
    }

    /// Whether the user is to move in a game that is played in the app.
    public var isMyTurnAnywhere: Bool {
        unsortedGames.contains { $0.isPlayableHere && $0.isMyTurn }
    }

    public mutating func apply(_ event: LichessEvent, userID: String) {
        switch event {
        case .gameStart(let game):
            // An accepted challenge turns into a game with the same id.
            removeChallenge(id: game.id)
            if let index = unsortedGames.firstIndex(where: { $0.id == game.id }) {
                unsortedGames[index] = game
            } else {
                unsortedGames.append(game)
            }
        case .gameFinish(let game):
            unsortedGames.removeAll { $0.id == game.id }
        case .challenge(let challenge):
            removeChallenge(id: challenge.id)
            if challenge.isIncoming(forUserID: userID) {
                incomingChallenges.append(challenge)
            } else {
                outgoingChallenges.append(challenge)
            }
        case .challengeCanceled(let id), .challengeDeclined(let id):
            removeChallenge(id: id)
        case .other:
            break
        }
    }

    /// Takes over the list of ongoing games as Lichess reports it.
    public mutating func replaceGames(_ games: [LichessGameInfo]) {
        unsortedGames = games
    }

    public mutating func setMyTurn(_ isMyTurn: Bool, inGame id: String) {
        guard let index = unsortedGames.firstIndex(where: { $0.id == id }) else { return }
        unsortedGames[index].isMyTurn = isMyTurn
    }

    public mutating func removeChallenge(id: String) {
        incomingChallenges.removeAll { $0.id == id }
        outgoingChallenges.removeAll { $0.id == id }
    }
}
