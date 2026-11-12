import Foundation

/// The Lichess API calls the app uses. Sends one request at a time and backs off after a 429.
public actor LichessClient {
    private let transport: any HTTPTransport
    private let userAgent: String
    private let now: @Sendable () -> Date
    private var token: String?
    private var blockedUntil: Date?
    /// The most recently queued request. The next one waits for it.
    private var lastRequest: Task<Void, Never>?

    private static let base = URL(string: "https://lichess.org")!

    public init(transport: any HTTPTransport = URLSessionTransport(), userAgent: String,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.transport = transport
        self.userAgent = userAgent
        self.now = now
    }

    public func setToken(_ token: String?) {
        self.token = token
    }

    // MARK: - Login

    /// Trades the authorization code from the login for an access token.
    public func exchangeCode(_ code: String, for request: OAuthRequest) async throws -> String {
        struct TokenResponse: Decodable { let access_token: String }
        let form = [
            "grant_type": "authorization_code", "code": code, "code_verifier": request.codeVerifier,
            "redirect_uri": request.redirectURI, "client_id": request.clientID,
        ]
        let response = try await perform("POST", "/api/token", form: form, authorized: false)
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: response.body) else {
            throw LichessError.invalidResponse
        }
        return token.access_token
    }

    public func account() async throws -> LichessAccount {
        let response = try await perform("GET", "/api/account")
        guard let account = try? JSONDecoder().decode(LichessAccount.self, from: response.body) else {
            throw LichessError.invalidResponse
        }
        return account
    }

    /// Makes the current token invalid on Lichess.
    public func revokeToken() async throws {
        _ = try await perform("DELETE", "/api/token")
    }

    // MARK: - Games

    public func ongoingGames() async throws -> [LichessGameInfo] {
        let response = try await perform("GET", "/api/account/playing?nb=50")
        return try LichessGameInfo.list(fromPlayingJSON: response.body)
    }

    public func move(_ move: Move, inGame id: String) async throws {
        _ = try await perform("POST", "/api/board/game/\(id)/move/\(move.uci)")
    }

    public func resign(game id: String) async throws {
        _ = try await perform("POST", "/api/board/game/\(id)/resign")
    }

    /// `true` offers a draw or accepts the opponent's offer, `false` declines it.
    public func answerDraw(_ accept: Bool, inGame id: String) async throws {
        _ = try await perform("POST", "/api/board/game/\(id)/draw/\(accept ? "yes" : "no")")
    }

    // MARK: - Challenges

    public func acceptChallenge(_ id: String) async throws {
        _ = try await perform("POST", "/api/challenge/\(id)/accept")
    }

    public func declineChallenge(_ id: String) async throws {
        _ = try await perform("POST", "/api/challenge/\(id)/decline")
    }

    /// Challenges `user` to an unrated correspondence game. `color` is the user's own colour, `nil` for random.
    public func challenge(user: String, daysPerMove: Int, color: PieceColor?) async throws {
        let name = user.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? user
        let form = ["days": String(daysPerMove), "color": color?.rawValue ?? "random", "rated": "false"]
        _ = try await perform("POST", "/api/challenge/\(name)", form: form)
    }

    // MARK: - Streams

    /// The user's events: games starting and ending, challenges. Lichess allows one such stream per token.
    public func events() async throws -> AsyncThrowingStream<LichessEvent, any Error> {
        try await stream("/api/stream/event") { try? LichessEvent(line: $0) }
    }

    /// The state of one game. The first event is the full game.
    public func gameEvents(game id: String) async throws -> AsyncThrowingStream<LichessGameEvent, any Error> {
        try await stream("/api/board/game/stream/\(id)") { try? LichessGameEvent(line: $0) }
    }

    private func stream<Event: Sendable>(
        _ path: String, decode: @escaping @Sendable (String) -> Event?
    ) async throws -> AsyncThrowingStream<Event, any Error> {
        let request = try self.request("GET", path, accept: "application/x-ndjson")
        let response: HTTPStream
        do {
            response = try await transport.stream(request)
        } catch {
            throw LichessError.offline
        }
        try check(status: response.status, body: Data())

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    // Empty keep-alive lines and lines that cannot be read are skipped.
                    for try await line in response.lines where !line.isEmpty {
                        if let event = decode(line) { continuation.yield(event) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: LichessError.offline)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Plumbing

    private func request(
        _ method: String, _ path: String, form: [String: String]? = nil, authorized: Bool = true,
        accept: String = "application/json"
    ) throws -> HTTPRequest {
        if let blockedUntil {
            guard now() >= blockedUntil else { throw LichessError.rateLimited(until: blockedUntil) }
            self.blockedUntil = nil
        }
        var headers = ["Accept": accept, "User-Agent": userAgent]
        if authorized {
            guard let token else { throw LichessError.unauthorized }
            headers["Authorization"] = "Bearer \(token)"
        }
        var body: Data?
        if let form {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            let encoded = form.sorted { $0.key < $1.key }.map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            body = Data(encoded.joined(separator: "&").utf8)
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        }
        return HTTPRequest(method: method, url: URL(string: path, relativeTo: Self.base)!.absoluteURL,
                           headers: headers, body: body)
    }

    private func perform(
        _ method: String, _ path: String, form: [String: String]? = nil, authorized: Bool = true
    ) async throws -> HTTPResponse {
        // Lichess asks for one request at a time, so each request waits for the one before it.
        let previous = lastRequest
        let transport = transport
        let task = Task { () throws -> HTTPResponse in
            await previous?.value
            let request = try self.request(method, path, form: form, authorized: authorized)
            do {
                return try await transport.send(request)
            } catch {
                throw LichessError.offline
            }
        }
        lastRequest = Task { _ = await task.result }

        let response = try await task.value
        try check(status: response.status, body: response.body)
        return response
    }

    private func check(status: Int, body: Data) throws {
        struct ErrorBody: Decodable { let error: String }
        switch status {
        case 200..<300:
            return
        case 401:
            throw LichessError.unauthorized
        case 429:
            let until = now().addingTimeInterval(60)
            blockedUntil = until
            throw LichessError.rateLimited(until: until)
        default:
            throw LichessError.http(status, (try? JSONDecoder().decode(ErrorBody.self, from: body))?.error)
        }
    }
}
