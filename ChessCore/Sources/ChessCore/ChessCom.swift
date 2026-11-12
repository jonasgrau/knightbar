import Foundation

public enum ChessComError: Error, Equatable, Sendable {
    /// Chess.com knows no player of that name, or no name was given.
    case userNotFound
    /// Chess.com asked for a pause. No request is sent before `until`.
    case rateLimited(until: Date)
    case http(Int)
    /// The request did not reach Chess.com.
    case offline
    case invalidResponse
}

/// A Chess.com daily game in which the player is to move.
public struct ChessComGame: Hashable, Sendable, Identifiable {
    /// The game's page on chess.com.
    public var url: URL
    /// When the player's time for this move runs out.
    public var moveBy: Date?

    public init(url: URL, moveBy: Date?) {
        self.url = url
        self.moveBy = moveBy
    }

    public var id: String { url.lastPathComponent }

    /// The time left for the move in words, e.g. "2 days left". `nil` if the game has no deadline.
    public func timeLeftText(at now: Date) -> String? {
        guard let moveBy else { return nil }
        let seconds = Int(moveBy.timeIntervalSince(now))
        func text(_ count: Int, _ unit: String) -> String {
            "\(count) \(unit)\(count == 1 ? "" : "s") left"
        }
        switch seconds {
        case ...0: return "Time is up"
        case ..<60: return "Less than a minute left"
        case ..<3_600: return text(seconds / 60, "minute")
        case ..<86_400: return text(seconds / 3_600, "hour")
        default: return text(seconds / 86_400, "day")
        }
    }
}

/// Asks Chess.com's published-data API in which daily games a player is to move.
///
/// The API is read-only and needs no login. Moves are made on chess.com itself.
public actor ChessComClient {
    private struct Remembered {
        let username: String
        let etag: String
        let games: [ChessComGame]
    }

    private let transport: any HTTPTransport
    private let userAgent: String
    private let now: @Sendable () -> Date
    /// The last answer, so that an unchanged one need not be sent again.
    private var remembered: Remembered?
    private var blockedUntil: Date?

    public init(transport: any HTTPTransport = URLSessionTransport(), userAgent: String,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.userAgent = userAgent
        self.now = now
    }

    /// The daily games in which `username` has to move, from `GET /pub/player/{username}/games/to-move`.
    public func gamesToMove(for username: String) async throws(ChessComError) -> [ChessComGame] {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        guard !name.isEmpty,
              let escaped = name.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "https://api.chess.com/pub/player/\(escaped)/games/to-move")
        else { throw .userNotFound }

        if let blockedUntil {
            guard now() >= blockedUntil else { throw .rateLimited(until: blockedUntil) }
            self.blockedUntil = nil
        }

        var headers = ["Accept": "application/json", "User-Agent": userAgent]
        let known = remembered?.username == name ? remembered : nil
        if let known { headers["If-None-Match"] = known.etag }

        let response: HTTPResponse
        do {
            response = try await transport.send(HTTPRequest(url: url, headers: headers))
        } catch {
            throw .offline
        }

        switch response.status {
        case 200:
            let games = try Self.decode(response.body)
            remembered = response.header("ETag").map { Remembered(username: name, etag: $0, games: games) }
            return games
        case 304:
            guard let known else { throw .invalidResponse }
            return known.games
        case 404:
            throw .userNotFound
        case 429:
            let until = now().addingTimeInterval(60)
            blockedUntil = until
            throw .rateLimited(until: until)
        default:
            throw .http(response.status)
        }
    }

    private static func decode(_ data: Data) throws(ChessComError) -> [ChessComGame] {
        struct Response: Decodable {
            struct Game: Decodable {
                let url: URL
                let move_by: Int?
            }
            let games: [Game]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { throw .invalidResponse }
        return response.games.map { game in
            // Chess.com writes 0 when a game has no deadline for the move.
            let deadline = game.move_by.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
            return ChessComGame(url: game.url, moveBy: deadline)
        }
    }
}
