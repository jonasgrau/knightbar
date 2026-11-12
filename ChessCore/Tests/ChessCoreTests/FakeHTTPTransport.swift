import ChessCore
import Foundation

/// Answers requests from a script and records what was asked.
final class FakeHTTPTransport: HTTPTransport, @unchecked Sendable {
    /// A scripted streaming response: the lines to deliver, then how the stream ends.
    struct Stream {
        var status = 200
        var lines: [String] = []
        /// `nil` ends the stream normally; an error makes it fail after the lines.
        var failure: URLError?
        /// Keeps the stream open after the lines until the consumer stops listening.
        var staysOpen = false
    }

    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    private var replies: [Result<HTTPResponse, URLError>]
    private var streams: [Stream]

    init(_ replies: [Result<HTTPResponse, URLError>] = [], streams: [Stream] = []) {
        self.replies = replies
        self.streams = streams
    }

    var requests: [HTTPRequest] { lock.withLock { recorded } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        let reply = lock.withLock {
            recorded.append(request)
            return replies.isEmpty ? .success(HTTPResponse(status: 599, body: Data())) : replies.removeFirst()
        }
        return try reply.get()
    }

    func stream(_ request: HTTPRequest) async throws -> HTTPStream {
        let script = lock.withLock {
            recorded.append(request)
            return streams.isEmpty ? Stream(status: 599) : streams.removeFirst()
        }
        let lines = AsyncThrowingStream<String, any Error> { continuation in
            for line in script.lines { continuation.yield(line) }
            if let failure = script.failure {
                continuation.finish(throwing: failure)
            } else if !script.staysOpen {
                continuation.finish()
            }
        }
        return HTTPStream(status: script.status, lines: lines)
    }
}

func ok(_ body: String = #"{"ok":true}"#) -> Result<HTTPResponse, URLError> {
    .success(HTTPResponse(status: 200, body: Data(body.utf8)))
}

func status(_ code: Int, _ body: String = "") -> Result<HTTPResponse, URLError> {
    .success(HTTPResponse(status: code, body: Data(body.utf8)))
}
