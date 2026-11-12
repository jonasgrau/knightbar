import Foundation
import Testing
import ChessCore

@Suite struct SANTests {
    @Test(arguments: [
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "e2e4", "e4"),
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "g1f3", "Nf3"),
        ("rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2", "e4d5", "exd5"),
        ("rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3", "e5f6", "exf6"),
        ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", "e1g1", "O-O"),
        ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", "e1c1", "O-O-O"),
        ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", "f3f6", "Qxf6"),
        ("8/P7/8/8/8/8/8/k1K5 w - - 0 1", "a7a8q", "a8=Q#"),
        ("8/P7/8/8/8/8/8/k1K5 w - - 0 1", "a7a8n", "a8=N"),
        ("4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1", "b1d2", "Nbd2"),
        ("4k3/8/8/8/R7/8/8/R3K3 w - - 0 1", "a1a2", "R1a2"),
        ("8/6k1/8/8/4Q2Q/8/8/K6Q w - - 0 1", "h4e1", "Qh4e1"),
        ("4k3/8/8/8/8/8/8/R3K3 w - - 0 1", "a1a8", "Ra8+"),
        ("5k2/8/8/8/8/8/8/4K2R w K - 0 1", "e1g1", "O-O+"),
    ])
    func moveIsWrittenInStandardAlgebraicNotation(fen: String, uci: String, san: String) throws {
        #expect(try Position(fen: fen).san(for: Move(uci: uci)!) == san)
    }

    @Test func pinnedPieceNeedsNoDisambiguation() throws {
        // The knight on d2 is pinned, so only the one on g1 can go to f3.
        let position = try Position(fen: "4k3/8/8/8/1b6/8/3N4/4K1N1 w - - 0 1")
        #expect(position.san(for: Move(uci: "g1f3")!) == "Nf3")
    }
}

@Suite struct PGNTests {
    private func play(_ moves: String, from position: Position = .start) -> Game {
        var game = Game(position: position)
        for uci in moves.split(separator: " ") { game.make(Move(uci: String(uci))!) }
        return game
    }

    @Test func finishedGameExportsTagsMovesAndResult() {
        let pgn = play("f2f3 e7e5 g2g4 d8h4").pgn(tags: ["White": "Anna", "Black": "Ben", "Date": "2026.11.11"])
        #expect(pgn == """
            [Event "?"]
            [Site "?"]
            [Date "2026.11.11"]
            [Round "?"]
            [White "Anna"]
            [Black "Ben"]
            [Result "0-1"]

            1. f3 e5 2. g4 Qh4# 0-1

            """)
    }

    @Test func unfinishedGameEndsWithAsterisk() {
        let pgn = play("e2e4 e7e5 g1f3").pgn()
        #expect(pgn.contains("[Result \"*\"]"))
        #expect(pgn.hasSuffix("\n1. e4 e5 2. Nf3 *\n"))
    }

    @Test func drawnGameHasDrawResult() {
        let pgn = play("g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1 f6g8").pgn()
        #expect(pgn.contains("[Result \"1/2-1/2\"]"))
        #expect(pgn.hasSuffix(" 4. Ng1 Ng8 1/2-1/2\n"))
    }

    @Test func gameFromCustomPositionCarriesFENAndStartsWithBlackMoveNumber() throws {
        let fen = "4k3/8/8/8/8/8/4P3/4K3 b - - 0 7"
        let pgn = play("e8d7 e2e4", from: try Position(fen: fen)).pgn()
        #expect(pgn.contains("[SetUp \"1\"]\n[FEN \"\(fen)\"]\n"))
        #expect(pgn.hasSuffix("\n7... Kd7 8. e4 *\n"))
    }

    @Test func extraTagsFollowTheSevenTagRoster() {
        let pgn = Game().pgn(tags: ["Annotator": "x \"y\""])
        #expect(pgn.contains("[Result \"*\"]\n[Annotator \"x \\\"y\\\"\"]\n\n*\n"))
    }

    @Test func longMoveTextWrapsBelowEightyColumns() {
        var game = Game()
        let cycle = ["g1f3", "g8f6", "f3g1", "f6g8"]
        // Pawn moves in between prevent a repetition.
        let pawns = ["a2a3", "a7a6", "b2b3", "b7b6", "c2c3", "c7c6", "d2d3", "d7d6", "e2e3", "e7e6"]
        for pair in stride(from: 0, to: pawns.count, by: 2) {
            for uci in cycle + [pawns[pair], pawns[pair + 1]] { do { let made = game.make(Move(uci: uci)!); #expect(made) } }
        }
        let moveText = game.pgn().components(separatedBy: "\n\n")[1]
        let lines = moveText.split(separator: "\n")
        #expect(lines.count > 1)
        #expect(lines.allSatisfy { $0.count <= 80 })
    }
}
