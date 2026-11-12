import ChessCore
import Testing

@Suite struct SANParsingTests {
    @Test(arguments: [
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "e4", "e2e4"),
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "Nf3", "g1f3"),
        ("rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2", "exd5", "e4d5"),
        ("rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3", "exf6", "e5f6"),
        ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", "O-O", "e1g1"),
        ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", "O-O-O", "e1c1"),
        ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", "0-0", "e1g1"),
        ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", "Qxf6", "f3f6"),
        ("8/P7/8/8/8/8/8/k1K5 w - - 0 1", "a8=Q#", "a7a8q"),
        ("8/P7/8/8/8/8/8/k1K5 w - - 0 1", "a8=N", "a7a8n"),
        ("8/P7/8/8/8/8/8/k1K5 w - - 0 1", "a8R", "a7a8r"),
        ("4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1", "Nbd2", "b1d2"),
        ("4k3/8/8/8/R7/8/8/R3K3 w - - 0 1", "R1a2", "a1a2"),
        ("8/6k1/8/8/4Q2Q/8/8/K6Q w - - 0 1", "Qh4e1", "h4e1"),
        ("4k3/8/8/8/8/8/8/R3K3 w - - 0 1", "Ra8+", "a1a8"),
        ("4k3/8/8/8/8/8/8/R3K3 w - - 0 1", "Ra8+!?", "a1a8"),
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "Ng1f3", "g1f3"),
    ])
    func sanIsReadAsMove(fen: String, san: String, uci: String) throws {
        #expect(try Position(fen: fen).move(san: san) == Move(uci: uci))
    }

    @Test(arguments: [
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "e5"),     // not reachable
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "Nd2"),    // blocked by own pawn
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "O-O"),    // pieces in the way
        ("4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1", "Nd2"),                            // ambiguous
        ("8/P7/8/8/8/8/8/k1K5 w - - 0 1", "a8"),                                // promotion piece missing
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", ""),
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "hello"),
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "Xf3"),
    ])
    func invalidSANIsRejected(fen: String, san: String) throws {
        #expect(try Position(fen: fen).move(san: san) == nil)
    }

    @Test func everyLegalMoveSurvivesWritingAndReading() throws {
        let fens = [
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
            "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
        ]
        for fen in fens {
            let position = try Position(fen: fen)
            for move in position.legalMoves() {
                #expect(position.move(san: position.san(for: move)) == move, "\(move) in \(fen)")
            }
        }
    }
}

@Suite struct PGNReaderTests {
    @Test func tagsAndMovesAreRead() throws {
        let pgn = try PGNReader.read("""
            [Event "Test"]
            [White "Anna \\"the Rook\\" A."]

            1. f3 e5 2. g4 Qh4# 0-1
            """)
        #expect(pgn.tags == ["Event": "Test", "White": "Anna \"the Rook\" A."])
        #expect(pgn.startPosition == .start)
        #expect(pgn.moves.map(\.uci) == ["f2f3", "e7e5", "g2g4", "d8h4"])
    }

    @Test func fenTagSetsTheStartingPosition() throws {
        let pgn = try PGNReader.read("""
            [Date "????.??.??"]
            [Result "*"]
            [FEN "6k1/p2r2r1/3p2p1/3Np3/1p2p1nQ/5NK1/PPq5/7R w - - 0 1"]

            1. Qh8+ Kf7 2. Ng5#
            *
            """)
        #expect(pgn.startPosition.fen == "6k1/p2r2r1/3p2p1/3Np3/1p2p1nQ/5NK1/PPq5/7R w - - 0 1")
        #expect(pgn.moves.map(\.uci) == ["h4h8", "g8f7", "f3g5"])
    }

    @Test func commentsVariationsAndAnnotationsAreSkipped() throws {
        let pgn = try PGNReader.read("""
            1.e4 {best by test} e5 $1 (1... c5 2. Nf3 (2. c3 d5) 2... d6) 2. Nf3 ; rest of line is ignored 2... Qh4
            2... Nc6!? 3. Bb5 1/2-1/2
            """)
        #expect(pgn.moves.map(\.uci) == ["e2e4", "e7e5", "g1f3", "b8c6", "f1b5"])
    }

    @Test func blackMoveNumbersAreAccepted() throws {
        let pgn = try PGNReader.read("""
            [FEN "4k3/8/8/8/8/8/4P3/4K3 b - - 0 7"]

            7... Kd7 8. e4 *
            """)
        #expect(pgn.moves.map(\.uci) == ["e8d7", "e2e4"])
    }

    @Test func moveTextWithoutTagsIsRead() throws {
        #expect(try PGNReader.read("e4 e5 Nf3").moves.count == 3)
    }

    @Test func emptyMoveTextGivesNoMoves() throws {
        #expect(try PGNReader.read("[Event \"x\"]\n\n*").moves.isEmpty)
    }

    @Test func illegalMoveIsReported() {
        #expect(throws: PGNError.illegalMove("Ke3")) { try PGNReader.read("1. e4 e5 2. Ke3") }
    }

    @Test func brokenFENTagIsReported() {
        #expect(throws: PGNError.invalidFEN) { try PGNReader.read("[FEN \"nonsense\"]\n\n1. e4") }
    }

    @Test func exportedGameCanBeReadBack() throws {
        var game = Game()
        for uci in ["e2e4", "c7c5", "g1f3", "d7d6", "d2d4", "c5d4", "f3d4", "g8f6", "b1c3", "a7a6"] {
            game.make(Move(uci: uci)!)
        }
        let pgn = try PGNReader.read(game.pgn(tags: ["White": "A", "Black": "B"]))
        #expect(pgn.moves == game.moves)
        #expect(pgn.tags["White"] == "A")
    }
}
