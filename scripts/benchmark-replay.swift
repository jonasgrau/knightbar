import Foundation
import ChessCore
import CryptoKit

private struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
}

@main
struct ReplayBenchmark {
    /// Generate legal synthetic games outside every timed region. Prefer quiet moves to
    /// retain branching complexity, and irreversible moves before the fifty-move limit.
    private static func fixture(plies: Int, seed: UInt64, pawnOpening: Bool) -> Game {
        for attempt in 0..<32 {
            var random = SeededRandom(state: seed &+ UInt64(attempt))
            var game = Game()
            if pawnOpening {
                for file in "abcdefgh" {
                    for move in ["\(file)2\(file)4", "\(file)7\(file)5"] {
                        precondition(game.make(Move(uci: move)!))
                    }
                }
            }
            while game.moves.count < plies {
                let position = game.position
                let needsProgress = position.halfmoveClock >= 80
                let candidates = game.legalMoves.shuffled(using: &random).sorted { left, right in
                    func weight(_ move: Move) -> Int {
                        let pawn = position[move.from]?.kind == .pawn
                        let capture = position.isCapture(move)
                        return needsProgress ? (pawn || capture ? 0 : 10) : ((pawn ? 2 : 0) + (capture ? 4 : 0))
                    }
                    return weight(left) < weight(right)
                }
                var next: Game?
                for move in candidates {
                    var candidate = game
                    if candidate.make(move), !candidate.status.isOver { next = candidate; break }
                }
                guard let next else { break }
                game = next
            }
            if game.moves.count == plies { return game }
        }
        preconditionFailure("Could not generate the requested legal fixture")
    }

    private static func measure(_ label: String, plies: Int, samples: Int, body: () throws -> Int) rethrows {
        var checksum = 0
        for _ in 0..<3 { checksum &+= try body() }
        var times: [Double] = []
        for _ in 0..<samples {
            let start = DispatchTime.now().uptimeNanoseconds
            checksum &+= try body()
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        times.sort()
        let median = times[times.count / 2]
        let p95 = times[min(times.count - 1, Int(ceil(Double(times.count) * 0.95)) - 1)]
        print(String(format: "%@,%d,%.4f,%.4f,%d,%d", label, plies, median, p95, samples, checksum))
    }

    static func main() throws {
        let samples = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1])! : 31
        let seed = CommandLine.arguments.count > 2 ? UInt64(CommandLine.arguments[2])! : 42
        precondition(samples > 0)
        print("# Release replay benchmark; seed=\(seed); 1 full move = 2 plies")
        print("# Synthetic fixtures are generated and validated outside timed regions. No personal game data.")
        let folder = FileManager.default.temporaryDirectory.appending(path: "knightbar-replay-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SavedGameStore(fileURL: folder.appending(path: "game.json"))
        print("metric,plies,median_ms,p95_ms,samples,checksum")
        for pawnOpening in [false, true] {
            let name = pawnOpening ? "pawn-double-stress" : "quiet-synthetic"
            let full = fixture(plies: 600, seed: seed, pawnOpening: pawnOpening)
            let fingerprint = SHA256.hash(data: Data(full.moves.map(\.uci).joined(separator: " ").utf8))
                .map { String(format: "%02x", $0) }.joined()
            print("# \(name): \(full.positions.filter { $0.enPassantSquare != nil }.count) historical en passant positions; fixture_sha256=\(fingerprint)")
            for count in [80, 160, 300, 600] {
                let moves = Array(full.moves.prefix(count))
                let positions = Array(full.positions.prefix(count + 1))
                var game = Game()
                for move in moves { precondition(game.make(move)) }
                precondition(game.position == positions.last! && !game.status.isOver)
                let saved = SavedGame(game: game, playerColor: .white)
                try store.save(saved)
                try measure(name + "/saved-restore", plies: count, samples: samples) {
                    let restored = try saved.restoredGame()
                    precondition(restored.position == game.position && restored.moves == moves)
                    return restored.moves.count
                }
                try measure(name + "/disk-load-and-restore", plies: count, samples: samples) {
                    let restored = try store.load()!.restoredGame()
                    precondition(restored.position == game.position)
                    return restored.moves.count
                }
                for draws in [true, false] {
                    measure(name + (draws ? "/make-draws-on" : "/make-draws-off"), plies: count, samples: samples) {
                        var replayed = Game(automaticDraws: draws)
                        for move in moves { precondition(replayed.make(move)) }
                        precondition(replayed.position == game.position)
                        return replayed.moves.count
                    }
                }
                let event = try LichessGameEvent(line:
                    #"{"type":"gameFull","id":"benchmark","white":{"id":"synthetic","name":"Synthetic"},"black":{"id":"opponent","name":"Opponent"},"initialFen":"startpos","state":{"moves":"","status":"started"}}"#)
                guard case .full(let info) = event else { preconditionFailure("Invalid fixture") }
                var state = info.state
                state.moves = moves.map(\.uci)
                let base = try LichessGame(full: info, userID: "synthetic")
                try measure(name + "/lichess-apply", plies: count, samples: samples) {
                    var replayed = base
                    try replayed.apply(state)
                    precondition(replayed.game.position == game.position)
                    return replayed.game.moves.count
                }
                measure(name + "/legality-only", plies: count, samples: samples) {
                    var valid = 0
                    for (position, move) in zip(positions, moves) { if position.isLegal(move) { valid += 1 } }
                    precondition(valid == count)
                    return valid
                }
                measure(name + "/next-position-move-generation", plies: count, samples: samples) {
                    positions.dropFirst().reduce(0) { $0 + $1.legalMoves().count }
                }
            }
        }
    }
}
