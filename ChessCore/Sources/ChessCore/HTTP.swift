import Foundation

public struct HTTPRequest: Hashable, Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String = "GET", url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var body: Data
    public var headers: [String: String]

    public init(status: Int, body: Data, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }

    /// The value of a response header. Header names are compared without regard to case.
    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// A response whose body arrives line by line over a long time.
public struct HTTPStream: Sendable {
    public var status: Int
    public var lines: AsyncThrowingStream<String, any Error>

    public init(status: Int, lines: AsyncThrowingStream<String, any Error>) {
        self.status = status
        self.lines = lines
    }
}

/// The network access the clients need. Lets tests run without a network.
public protocol HTTPTransport: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
    /// Opens a streaming response. Stops when the consumer stops reading the lines.
    func stream(_ request: HTTPRequest) async throws -> HTTPStream
}

extension HTTPTransport {
    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try await send(HTTPRequest(url: url, headers: headers))
    }
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// Created on first use and shared by all transports; only streaming clients need it.
    private static let streamSession: URLSession = {
        // Lichess sends a keep-alive line every 7 seconds. A stream that stays silent for
        // 30 seconds is dead and fails, so that the caller can reconnect.
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    public init(session: URLSession = .shared) {
        self.session = session
    }

    private func urlRequest(_ request: HTTPRequest) -> URLRequest {
        var result = URLRequest(url: request.url)
        result.httpMethod = request.method
        result.httpBody = request.body
        for (name, value) in request.headers { result.setValue(value, forHTTPHeaderField: name) }
        return result
    }

    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: urlRequest(request))
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (name, value) in http?.allHeaderFields ?? [:] {
            if let name = name as? String, let value = value as? String { headers[name] = value }
        }
        return HTTPResponse(status: http?.statusCode ?? 0, body: data, headers: headers)
    }

    public func stream(_ request: HTTPRequest) async throws -> HTTPStream {
        let (bytes, response) = try await Self.streamSession.bytes(for: urlRequest(request))
        let lines = AsyncThrowingStream<String, any Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return HTTPStream(status: (response as? HTTPURLResponse)?.statusCode ?? 0, lines: lines)
    }
}
