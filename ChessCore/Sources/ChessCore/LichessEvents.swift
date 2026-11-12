import Foundation

public enum LichessError: Error, Equatable, Sendable {
    /// No token, or Lichess no longer accepts it.
    case unauthorized
    /// Lichess asked for a pause. No request is sent before `until`.
    case rateLimited(until: Date)
    /// Lichess refused the request. Carries its error message, if any.
    case http(Int, String?)
    /// The request did not reach Lichess, or a stream broke off.
    case offline
    case invalidResponse
}

public struct LichessAccount: Hashable, Sendable, Codable {
    public var id: String
    public var username: String

    public init(id: String, username: String) {
        self.id = id
        self.username = username
    }
}

/// An ongoing game as the event stream and the list of ongoing games describe it.
public struct LichessGameInfo: Hashable, Sendable, Identifiable {
    public var id: String
    /// The user's colour.
    public var color: PieceColor
    public var fen: String
    public var lastMove: Move?
    public var isMyTurn: Bool
    public var speed: String
    public var variant: String
    public var opponentName: String
    public var rated: Bool
    /// Whether the Board API may be used for this game.
    public var isBoardCompatible: Bool

    public var isCorrespondence: Bool { speed == "correspondence" }

    /// Whether the game is played in the app: standard correspondence chess the Board API allows.
    /// Other games are only listed with a link to Lichess.
    public var isPlayableHere: Bool { isBoardCompatible && isCorrespondence && variant == "standard" }

    public var url: URL { URL(string: "https://lichess.org/\(id)")! }

    /// Decodes the response of `GET /api/account/playing`.
    public static func list(fromPlayingJSON data: Data) throws -> [LichessGameInfo] {
        struct Playing: Decodable { let nowPlaying: [GameDTO] }
        guard let playing = try? JSONDecoder().decode(Playing.self, from: data) else {
            throw LichessError.invalidResponse
        }
        return playing.nowPlaying.map(\.info)
    }
}

public struct LichessChallenge: Hashable, Sendable, Identifiable {
    public var id: String
    public var challengerID: String
    public var challengerName: String
    public var destUserName: String?
    public var speed: String
    public var variant: String
    public var rated: Bool
    public var daysPerTurn: Int?
    public var isBoardCompatible: Bool

    /// Whether the challenge was sent to the user rather than by them.
    public func isIncoming(forUserID userID: String) -> Bool {
        challengerID.lowercased() != userID.lowercased()
    }

    public var url: URL { URL(string: "https://lichess.org/\(id)")! }
}

/// A line of `GET /api/stream/event`.
public enum LichessEvent: Hashable, Sendable {
    case gameStart(LichessGameInfo)
    case gameFinish(LichessGameInfo)
    case challenge(LichessChallenge)
    case challengeCanceled(id: String)
    case challengeDeclined(id: String)
    /// An event type this app does not use.
    case other

    public init(line: String) throws {
        struct Envelope: Decodable {
            let type: String
            let game: GameDTO?
            let challenge: ChallengeDTO?
            let compat: CompatDTO?
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(line.utf8)) else {
            throw LichessError.invalidResponse
        }
        switch (envelope.type, envelope.game, envelope.challenge) {
        case ("gameStart", let game?, _): self = .gameStart(game.info)
        case ("gameFinish", let game?, _): self = .gameFinish(game.info)
        case ("challenge", _, let challenge?): self = .challenge(challenge.challenge(compat: envelope.compat))
        case ("challengeCanceled", _, let challenge?): self = .challengeCanceled(id: challenge.id)
        case ("challengeDeclined", _, let challenge?): self = .challengeDeclined(id: challenge.id)
        default: self = .other
        }
    }
}

public struct LichessGameState: Hashable, Sendable {
    /// All moves of the game so far, in UCI notation.
    public var moves: [String]
    /// Lichess's status name, e.g. "started", "mate" or "resign".
    public var status: String
    public var winner: PieceColor?
    public var whiteOffersDraw: Bool
    public var blackOffersDraw: Bool
}

public struct LichessGameFull: Hashable, Sendable {
    public var id: String
    public var whiteID: String?
    public var whiteName: String
    public var blackID: String?
    public var blackName: String
    /// A FEN, or "startpos".
    public var initialFEN: String
    public var state: LichessGameState
}

/// A line of `GET /api/board/game/stream/{gameId}`.
public enum LichessGameEvent: Hashable, Sendable {
    case full(LichessGameFull)
    case state(LichessGameState)
    /// Chat lines and other events this app does not use.
    case other

    public init(line: String) throws {
        struct TypeOnly: Decodable { let type: String }
        let data = Data(line.utf8)
        let decoder = JSONDecoder()
        guard let type = try? decoder.decode(TypeOnly.self, from: data).type else {
            throw LichessError.invalidResponse
        }
        switch type {
        case "gameFull":
            guard let full = try? decoder.decode(GameFullDTO.self, from: data) else { throw LichessError.invalidResponse }
            self = .full(full.full)
        case "gameState":
            guard let state = try? decoder.decode(GameStateDTO.self, from: data) else { throw LichessError.invalidResponse }
            self = .state(state.state)
        default:
            self = .other
        }
    }
}

// MARK: - JSON shapes

private struct CompatDTO: Decodable {
    let board: Bool?
}

private struct GameDTO: Decodable {
    struct Opponent: Decodable {
        let username: String?
        let ai: Int?
    }
    struct Variant: Decodable {
        let key: String
    }

    let gameId: String
    let fen: String
    let color: PieceColor
    let lastMove: String?
    let variant: Variant?
    let speed: String
    let rated: Bool?
    let opponent: Opponent?
    let isMyTurn: Bool?
    let compat: CompatDTO?

    var info: LichessGameInfo {
        LichessGameInfo(
            id: gameId, color: color, fen: fen, lastMove: lastMove.flatMap(Move.init(uci:)),
            isMyTurn: isMyTurn ?? false, speed: speed, variant: variant?.key ?? "standard",
            opponentName: opponent?.username ?? opponent?.ai.map { "Stockfish level \($0)" } ?? "Opponent",
            rated: rated ?? false,
            // The list of ongoing games carries no compatibility flag.
            isBoardCompatible: compat?.board ?? true)
    }
}

private struct ChallengeDTO: Decodable {
    struct User: Decodable {
        let id: String
        let name: String
    }
    struct Variant: Decodable {
        let key: String
    }
    struct TimeControl: Decodable {
        let daysPerTurn: Int?
    }

    let id: String
    let challenger: User?
    let destUser: User?
    let variant: Variant?
    let rated: Bool?
    let speed: String?
    let timeControl: TimeControl?

    func challenge(compat: CompatDTO?) -> LichessChallenge {
        LichessChallenge(
            id: id, challengerID: challenger?.id ?? "", challengerName: challenger?.name ?? "Someone",
            destUserName: destUser?.name, speed: speed ?? "", variant: variant?.key ?? "standard",
            rated: rated ?? false, daysPerTurn: timeControl?.daysPerTurn,
            isBoardCompatible: compat?.board ?? false)
    }
}

private struct GameStateDTO: Decodable {
    let moves: String
    let status: String
    let winner: PieceColor?
    let wdraw: Bool?
    let bdraw: Bool?

    var state: LichessGameState {
        LichessGameState(
            moves: moves.split(separator: " ").map(String.init), status: status, winner: winner,
            whiteOffersDraw: wdraw ?? false, blackOffersDraw: bdraw ?? false)
    }
}

private struct GameFullDTO: Decodable {
    struct Player: Decodable {
        let id: String?
        let name: String?
        let aiLevel: Int?

        var displayName: String { name ?? aiLevel.map { "Stockfish level \($0)" } ?? "Opponent" }
    }

    let id: String
    let white: Player
    let black: Player
    let initialFen: String?
    let state: GameStateDTO

    var full: LichessGameFull {
        LichessGameFull(
            id: id, whiteID: white.id, whiteName: white.displayName, blackID: black.id,
            blackName: black.displayName, initialFEN: initialFen ?? "startpos", state: state.state)
    }
}
