import Foundation

public enum PuzzleClientError: Error, Equatable, Sendable {
    /// The server asked for a pause. No request is sent to it before `until`.
    case rateLimited(until: Date)
    case http(Int)
    /// The request did not reach the server.
    case offline
}

/// Fetches the daily puzzle from Lichess or Chess.com.
public actor PuzzleClient {
    private let transport: any HTTPTransport
    private let userAgent: String
    private let now: @Sendable () -> Date
    /// Hosts that answered 429, with the time until which they are left alone.
    private var blockedUntil: [String: Date] = [:]

    public init(transport: any HTTPTransport = URLSessionTransport(), userAgent: String,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.userAgent = userAgent
        self.now = now
    }

    public static func endpoint(for source: Puzzle.Source) -> URL {
        switch source {
        case .lichess: URL(string: "https://lichess.org/api/puzzle/daily")!
        case .chessCom: URL(string: "https://api.chess.com/pub/puzzle")!
        }
    }

    /// The raw response of the source's daily puzzle endpoint. Decode it with `Puzzle(source:data:)`.
    public func dailyPuzzleData(from source: Puzzle.Source) async throws(PuzzleClientError) -> Data {
        let url = Self.endpoint(for: source)
        let host = url.host() ?? ""
        if let until = blockedUntil[host] {
            guard now() >= until else { throw .rateLimited(until: until) }
            blockedUntil[host] = nil
        }

        let response: HTTPResponse
        do {
            response = try await transport.get(url, headers: ["Accept": "application/json", "User-Agent": userAgent])
        } catch {
            throw .offline
        }

        switch response.status {
        case 200:
            return response.body
        case 429:
            // Both services ask clients to wait a full minute after a 429.
            let until = now().addingTimeInterval(60)
            blockedUntil[host] = until
            throw .rateLimited(until: until)
        default:
            throw .http(response.status)
        }
    }
}

/// Keeps the last response per source on disk, so the puzzle is there without a network.
public struct PuzzleCache: Sendable {
    public struct Entry: Hashable, Sendable, Codable {
        public var data: Data
        public var fetchedAt: Date

        public init(data: Data, fetchedAt: Date) {
            self.data = data
            self.fetchedAt = fetchedAt
        }

        /// A response is not fetched again within 15 minutes.
        public func isFresh(at date: Date) -> Bool {
            date.timeIntervalSince(fetchedAt) < 15 * 60
        }
    }

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    private func fileURL(for source: Puzzle.Source) -> URL {
        folder.appending(path: "puzzle-\(source.rawValue).json")
    }

    public func entry(for source: Puzzle.Source) -> Entry? {
        guard let data = try? Data(contentsOf: fileURL(for: source)) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    public func store(_ data: Data, for source: Puzzle.Source, fetchedAt: Date) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(Entry(data: data, fetchedAt: fetchedAt))
            .write(to: fileURL(for: source), options: .atomic)
    }
}
