import Testing
import ChessCore

@Suite struct FENTests {
    static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    static let kiwipeteFEN = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"

    @Test func startPositionWritesStandardFEN() {
        #expect(Position.start.fen == Self.startFEN)
    }

    @Test(arguments: [
        startFEN,
        kiwipeteFEN,
        "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3",
        "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 b - - 12 34",
        "r3k2r/8/8/8/8/8/8/R3K2R b Kq - 3 20",
    ])
    func fenSurvivesRoundTrip(fen: String) throws {
        #expect(try Position(fen: fen).fen == fen)
    }

    @Test func parsedPositionExposesPiecesAndState() throws {
        let position = try Position(fen: "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3")
        #expect(position[Square("e5")!] == Piece(color: .white, kind: .pawn))
        #expect(position[Square("d8")!] == Piece(color: .black, kind: .queen))
        #expect(position[Square("e4")!] == nil)
        #expect(position.sideToMove == .white)
        #expect(position.enPassantSquare == Square("f6"))
        #expect(position.halfmoveClock == 0)
        #expect(position.fullmoveNumber == 3)
    }

    @Test func missingClocksDefaultToZeroAndOne() throws {
        let position = try Position(fen: "4k3/8/8/8/8/8/4P3/4K3 w - -")
        #expect(position.fen == "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1")
    }

    @Test(arguments: [
        "",
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1",          // only 7 ranks
        "rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", // rank too long
        "rnbqkbnr/pppppppp/7/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", // rank too short
        "rnbqkbnr/ppppxppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", // unknown piece
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1", // side to move
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KXkq - 0 1", // castling
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e5 0 1", // En passant
        "4k3/8/8/3Pn3/8/8/8/4K3 w - e6 0 1",                       // en passant: knight, not pawn, on e5
        "4k3/8/8/3P4/8/8/8/4K3 w - e6 0 1",                        // en passant: no pawn on e5
        "4k3/4p3/8/3Pp3/8/8/8/4K3 w - e6 0 1",                     // en passant: e7 not empty
        "4k3/8/4n3/3Pp3/8/8/8/4K3 w - e6 0 1",                     // en passant: e6 not empty
        "4k3/8/8/8/3pP3/4N3/8/4K3 b - e3 0 1",                     // en passant: e3 not empty
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - x 1", // halfmove clock
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 0", // move number
        "rnbq1bnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQ - 0 1",   // no black king
        "4k3/8/8/8/8/8/8/P3K3 w - - 0 1",                           // pawn on rank 1
    ])
    func invalidFENIsRejected(fen: String) {
        #expect(throws: FENError.self) { try Position(fen: fen) }
    }
}
