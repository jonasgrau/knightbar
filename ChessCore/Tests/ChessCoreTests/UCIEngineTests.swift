import ChessCore
import Foundation
import Testing

@Suite struct UCIEngineTests {
    private let short = Duration.milliseconds(150)

    private func startedEngine(_ transport: FakeEngineTransport) async throws -> UCIEngine {
        let engine = UCIEngine(transport: transport, timeout: short)
        try await engine.start()
        return engine
    }

    @Test func startPerformsTheUCIHandshake() async throws {
        let transport = FakeEngineTransport()
        _ = try await startedEngine(transport)
        #expect(transport.sent == ["uci", "isready"])
    }

    @Test func startFailsWithTimeoutWhenTheEngineStaysSilent() async {
        let engine = UCIEngine(transport: FakeEngineTransport { _ in [] }, timeout: short)
        await #expect(throws: EngineError.timeout) { try await engine.start() }
    }

    @Test func failedStartEndsTheEngineProcess() async {
        let transport = FakeEngineTransport { _ in [] }
        let engine = UCIEngine(transport: transport, timeout: short)
        await #expect(throws: EngineError.timeout) { try await engine.start() }
        #expect(transport.wasTerminated)
    }

    @Test func busyEngineRejectsCommandsWithoutSendingThem() async throws {
        // This engine never finishes a search, so the first bestMove stays pending.
        let transport = FakeEngineTransport { command in
            command.hasPrefix("go") ? [] : FakeEngineTransport.wellBehaved(command)
        }
        let engine = try await startedEngine(transport)
        let search = Task { try await engine.bestMove(from: .start, moves: [], moveTime: .seconds(10)) }
        while !transport.sent.contains(where: { $0.hasPrefix("go") }) { await Task.yield() }
        let sentBefore = transport.sent

        await #expect(throws: EngineError.busy) { try await engine.setStrength(EngineStrength(level: 1)) }
        await #expect(throws: EngineError.busy) {
            try await engine.bestMove(from: .start, moves: [Move(uci: "e2e4")!], moveTime: .seconds(1))
        }
        #expect(transport.sent == sentBefore)
        search.cancel()
        await engine.shutdown()
    }

    @Test func startFailsWhenTheEngineExitsImmediately() async {
        let transport = FakeEngineTransport { _ in [] }
        transport.crash()
        let engine = UCIEngine(transport: transport, timeout: short)
        await #expect(throws: EngineError.terminated) { try await engine.start() }
    }

    @Test func limitedStrengthIsSentAsEloOptions() async throws {
        let transport = FakeEngineTransport()
        let engine = try await startedEngine(transport)
        try await engine.setStrength(EngineStrength(level: 1))
        #expect(transport.sent.suffix(3) == [
            "setoption name UCI_LimitStrength value true",
            "setoption name UCI_Elo value 1320",
            "isready",
        ])
    }

    @Test func fullStrengthSwitchesTheEloLimitOff() async throws {
        let transport = FakeEngineTransport()
        let engine = try await startedEngine(transport)
        try await engine.setStrength(EngineStrength(level: 8))
        #expect(transport.sent.suffix(2) == ["setoption name UCI_LimitStrength value false", "isready"])
    }

    @Test func bestMoveSendsPositionAndMoveTimeAndReturnsTheReply() async throws {
        let transport = FakeEngineTransport()
        let engine = try await startedEngine(transport)
        let move = try await engine.bestMove(
            from: .start, moves: [Move(uci: "e2e4")!], moveTime: .milliseconds(500))
        #expect(move == Move(uci: "e7e5"))
        #expect(transport.sent.suffix(2) == ["position startpos moves e2e4", "go movetime 500"])
    }

    @Test func bestMoveFromACustomPositionSendsItsFEN() async throws {
        let transport = FakeEngineTransport()
        let engine = try await startedEngine(transport)
        let fen = "4k3/8/8/8/8/8/4P3/4K3 b - - 0 1"
        _ = try await engine.bestMove(from: try Position(fen: fen), moves: [], moveTime: .seconds(1))
        #expect(transport.sent.suffix(2) == ["position fen \(fen)", "go movetime 1000"])
    }

    @Test func promotionReplyIsParsed() async throws {
        let transport = FakeEngineTransport { command in
            command.hasPrefix("go") ? ["bestmove a7a8q"] : FakeEngineTransport.wellBehaved(command)
        }
        let engine = try await startedEngine(transport)
        let move = try await engine.bestMove(from: .start, moves: [], moveTime: .seconds(1))
        #expect(move == Move(uci: "a7a8q"))
    }

    @Test func missingBestMoveIsReportedAsInvalidResponse() async throws {
        let transport = FakeEngineTransport { command in
            command.hasPrefix("go") ? ["bestmove (none)"] : FakeEngineTransport.wellBehaved(command)
        }
        let engine = try await startedEngine(transport)
        await #expect(throws: EngineError.invalidResponse("bestmove (none)")) {
            try await engine.bestMove(from: .start, moves: [], moveTime: .seconds(1))
        }
    }

    @Test func searchTimesOutWhenNoBestMoveArrives() async throws {
        let transport = FakeEngineTransport { command in
            command.hasPrefix("go") ? ["info depth 1"] : FakeEngineTransport.wellBehaved(command)
        }
        let engine = try await startedEngine(transport)
        await #expect(throws: EngineError.timeout) {
            try await engine.bestMove(from: .start, moves: [], moveTime: .milliseconds(50))
        }
    }

    @Test func searchFailsWhenTheEngineDiesWhileThinking() async throws {
        let transport = FakeEngineTransport { command in
            command.hasPrefix("go") ? [] : FakeEngineTransport.wellBehaved(command)
        }
        let engine = try await startedEngine(transport)
        let search = Task { try await engine.bestMove(from: .start, moves: [], moveTime: .seconds(5)) }
        try await Task.sleep(for: .milliseconds(50))
        transport.crash()
        await #expect(throws: EngineError.terminated) { try await search.value }
    }

    @Test func cancelSearchAsksTheEngineToStop() async throws {
        let transport = FakeEngineTransport { command in
            switch command {
            case let go where go.hasPrefix("go"): []
            case "stop": ["bestmove g1f3"]
            default: FakeEngineTransport.wellBehaved(command)
            }
        }
        let engine = try await startedEngine(transport)
        let search = Task { try await engine.bestMove(from: .start, moves: [], moveTime: .seconds(5)) }
        try await Task.sleep(for: .milliseconds(50))
        await engine.cancelSearch()
        let move = try await search.value
        #expect(move == Move(uci: "g1f3"))
        #expect(transport.sent.last == "stop")
    }

    @Test func cancelSearchDoesNothingWhenIdle() async throws {
        let transport = FakeEngineTransport()
        let engine = try await startedEngine(transport)
        await engine.cancelSearch()
        #expect(transport.sent == ["uci", "isready"])
    }

    @Test func shutdownSendsQuit() async throws {
        let transport = FakeEngineTransport()
        let engine = try await startedEngine(transport)
        await engine.shutdown()
        #expect(transport.sent.last == "quit")
        #expect(!transport.wasTerminated)
    }

    @Test func shutdownKillsAnEngineThatIgnoresQuit() async throws {
        final class Stubborn: EngineTransport, @unchecked Sendable {
            let base = FakeEngineTransport()
            var lines: AsyncStream<String> { base.lines }
            func send(_ line: String) throws { if line != "quit" { try base.send(line) } }
            func terminate() { base.terminate() }
        }
        let transport = Stubborn()
        let engine = UCIEngine(transport: transport, timeout: short)
        try await engine.start()
        await engine.shutdown()
        #expect(transport.base.wasTerminated)
    }

    @Test func commandsAfterShutdownFail() async throws {
        let engine = try await startedEngine(FakeEngineTransport())
        await engine.shutdown()
        await #expect(throws: EngineError.terminated) {
            try await engine.bestMove(from: .start, moves: [], moveTime: .seconds(1))
        }
    }
}

@Suite struct EngineStrengthTests {
    @Test func levelsRunFromOneToEight() {
        #expect(EngineStrength.levels == 1...8)
        #expect(EngineStrength(level: 0).level == 1)
        #expect(EngineStrength(level: 12).level == 8)
    }

    @Test func eloRisesWithTheLevelAndTheTopLevelIsUnlimited() {
        let elos = EngineStrength.levels.map { EngineStrength(level: $0).elo }
        #expect(elos == [1320, 1500, 1700, 1900, 2100, 2300, 2600, nil])
    }
}

/// Runs against the real Stockfish binary when `scripts/fetch-stockfish.sh` has downloaded it.
@Suite struct StockfishIntegrationTests {
    static let binary = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Vendor/stockfish/stockfish")

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: binary.path)))
    func stockfishFindsTheMateInOne() async throws {
        let engine = UCIEngine(transport: try ProcessTransport(executableURL: Self.binary))
        try await engine.start()
        try await engine.setStrength(EngineStrength(level: 8))
        let position = try Position(fen: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1")
        let move = try await engine.bestMove(from: position, moves: [], moveTime: .milliseconds(300))
        #expect(move == Move(uci: "a1a8"))
        await engine.shutdown()
    }

    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: binary.path)))
    func weakestLevelStillPlaysALegalMove() async throws {
        let engine = UCIEngine(transport: try ProcessTransport(executableURL: Self.binary))
        try await engine.start()
        try await engine.setStrength(EngineStrength(level: 1))
        let move = try await engine.bestMove(from: .start, moves: [Move(uci: "e2e4")!], moveTime: .milliseconds(200))
        #expect(Position.start.applying(Move(uci: "e2e4")!).isLegal(move))
        await engine.shutdown()
    }
}
