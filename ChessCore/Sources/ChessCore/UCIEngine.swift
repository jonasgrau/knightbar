public enum EngineError: Error, Equatable, Sendable {
    /// The engine did not answer in time.
    case timeout
    /// The engine process has ended or was shut down.
    case terminated
    /// Another request is still waiting for its answer.
    case busy
    case invalidResponse(String)
}

/// A line-based connection to a UCI engine.
public protocol EngineTransport: Sendable {
    /// The lines the engine prints. The stream ends when the engine exits.
    var lines: AsyncStream<String> { get }
    func send(_ line: String) throws
    /// Ends the engine by force.
    func terminate()
}

/// Talks to a chess engine over the Universal Chess Interface.
public actor UCIEngine {
    private struct Waiter {
        let id: Int
        let matches: @Sendable (String) -> Bool
        let continuation: CheckedContinuation<String, any Error>
        let timeoutTask: Task<Void, Never>
    }

    private let transport: any EngineTransport
    private let timeout: Duration
    private var reader: Task<Void, Never>?
    private var waiter: Waiter?
    private var nextWaiterID = 0
    private var isClosed = false
    private var isSearching = false

    /// `timeout` is how long the engine may take to answer a command, on top of any thinking time.
    public init(transport: any EngineTransport, timeout: Duration = .seconds(5)) {
        self.transport = transport
        self.timeout = timeout
    }

    /// Performs the UCI handshake. Must be called once before anything else.
    public func start() async throws {
        if reader == nil {
            let lines = transport.lines
            reader = Task { [weak self] in
                for await line in lines { await self?.receive(line) }
                await self?.streamEnded()
            }
        }
        do {
            _ = try await request("uci", until: { $0 == "uciok" }, within: timeout)
            try await waitUntilReady()
        } catch {
            // The caller drops an engine that failed to start, so end its process here.
            close()
            throw error
        }
    }

    public func setStrength(_ strength: EngineStrength) async throws {
        try ensureIdle()
        for option in strength.uciOptions {
            try send("setoption name \(option.name) value \(option.value)")
        }
        try await waitUntilReady()
    }

    /// Lets the engine think for `moveTime` about the position reached from `start` by `moves`.
    public func bestMove(from start: Position, moves: [Move], moveTime: Duration) async throws -> Move {
        var position = start == .start ? "position startpos" : "position fen \(start.fen)"
        if !moves.isEmpty {
            position += " moves " + moves.map(\.uci).joined(separator: " ")
        }
        try ensureIdle()
        try send(position)

        let (seconds, attoseconds) = moveTime.components
        let milliseconds = seconds * 1000 + attoseconds / 1_000_000_000_000_000
        isSearching = true
        defer { isSearching = false }
        let reply: String
        do {
            reply = try await request(
                "go movetime \(milliseconds)", until: { $0.hasPrefix("bestmove") }, within: moveTime + timeout)
        } catch EngineError.timeout {
            // The engine is in an unknown state, and a late answer would be mistaken for the next one.
            close()
            throw EngineError.timeout
        }

        let words = reply.split(separator: " ")
        guard words.count >= 2, let move = Move(uci: String(words[1])) else {
            throw EngineError.invalidResponse(reply)
        }
        return move
    }

    /// Makes a running search return its best move so far right away.
    public func cancelSearch() {
        guard isSearching, !isClosed else { return }
        try? transport.send("stop")
    }

    /// Asks the engine to quit and kills it if it does not comply.
    public func shutdown() async {
        guard !isClosed else { return }
        try? transport.send("quit")
        let deadline = ContinuousClock.now + min(timeout, .seconds(1))
        while !isClosed, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        close()
    }

    // MARK: - Plumbing

    private func waitUntilReady() async throws {
        _ = try await request("isready", until: { $0 == "readyok" }, within: timeout)
    }

    /// Throws before anything is sent, so a refused command leaves the engine unchanged.
    /// UCI forbids most commands while the engine is searching.
    private func ensureIdle() throws {
        guard !isClosed else { throw EngineError.terminated }
        guard waiter == nil else { throw EngineError.busy }
    }

    private func send(_ command: String) throws {
        guard !isClosed else { throw EngineError.terminated }
        do {
            try transport.send(command)
        } catch {
            throw EngineError.terminated
        }
    }

    /// Sends `command` and returns the first line for which `matches` is true.
    private func request(
        _ command: String, until matches: @escaping @Sendable (String) -> Bool, within limit: Duration
    ) async throws -> String {
        guard !isClosed else { throw EngineError.terminated }
        guard waiter == nil else { throw EngineError.busy }
        let id = nextWaiterID
        nextWaiterID += 1
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                await self?.failWaiter(id: id, with: .timeout)
            }
            waiter = Waiter(id: id, matches: matches, continuation: continuation, timeoutTask: timeoutTask)
            do {
                try transport.send(command)
            } catch {
                failWaiter(id: id, with: .terminated)
            }
        }
    }

    private func receive(_ line: String) {
        guard let current = waiter, current.matches(line) else { return }
        waiter = nil
        current.timeoutTask.cancel()
        current.continuation.resume(returning: line)
    }

    private func failWaiter(id: Int, with error: EngineError) {
        guard let current = waiter, current.id == id else { return }
        waiter = nil
        current.timeoutTask.cancel()
        current.continuation.resume(throwing: error)
    }

    private func streamEnded() {
        isClosed = true
        if let waiter { failWaiter(id: waiter.id, with: .terminated) }
    }

    private func close() {
        guard !isClosed else { return }
        transport.terminate()
        streamEnded()
    }
}
