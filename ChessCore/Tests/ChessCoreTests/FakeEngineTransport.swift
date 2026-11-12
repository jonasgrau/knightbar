import ChessCore
import Foundation

/// A scripted stand-in for an engine process. `respond` maps each received command to the lines
/// the engine prints in return.
final class FakeEngineTransport: EngineTransport, @unchecked Sendable {
    let lines: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation
    private let lock = NSLock()
    private var sentLines: [String] = []
    private var terminated = false
    private let respond: @Sendable (String) -> [String]

    init(respond: @escaping @Sendable (String) -> [String] = FakeEngineTransport.wellBehaved) {
        self.respond = respond
        (lines, continuation) = AsyncStream.makeStream(of: String.self)
    }

    /// Answers the handshake and replies to every search with e7e5.
    static let wellBehaved: @Sendable (String) -> [String] = { command in
        switch command {
        case "uci": ["id name Fake", "option name Skill Level type spin default 20 min 0 max 20", "uciok"]
        case "isready": ["readyok"]
        case let go where go.hasPrefix("go"): ["info depth 1 score cp 20 pv e7e5", "bestmove e7e5 ponder g1f3"]
        default: []
        }
    }

    var sent: [String] { lock.withLock { sentLines } }
    var wasTerminated: Bool { lock.withLock { terminated } }

    func send(_ line: String) throws {
        lock.withLock { sentLines.append(line) }
        for reply in respond(line) { continuation.yield(reply) }
        if line == "quit" { continuation.finish() }
    }

    func terminate() {
        lock.withLock { terminated = true }
        continuation.finish()
    }

    /// Simulates the engine process dying.
    func crash() { continuation.finish() }
}
