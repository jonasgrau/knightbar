import Testing
import ChessCore

@Suite struct MoveGenerationTests {
    private func move(_ uci: String) -> Move { Move(uci: uci)! }

    @Test func moveParsesAndWritesUCI() {
        #expect(Move(uci: "e2e4") == Move(from: Square("e2")!, to: Square("e4")!))
        #expect(Move(uci: "e7e8q") == Move(from: Square("e7")!, to: Square("e8")!, promotion: .queen))
        #expect(move("a7a8n").uci == "a7a8n")
        #expect(Move(uci: "e2e9") == nil)
        #expect(Move(uci: "e7e8k") == nil)
        #expect(Move(uci: "e2") == nil)
    }

    @Test func squareNamesMapToFilesAndRanks() {
        #expect(Square("a1") == Square(file: 0, rank: 0))
        #expect(Square("h8") == Square(file: 7, rank: 7))
        #expect(Square(file: 4, rank: 3).name == "e4")
        #expect(Square("i1") == nil)
        #expect(Square("a9") == nil)
    }

    @Test func enPassantCaptureIsLegalAndRemovesThePawn() throws {
        let position = try Position(fen: "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3")
        #expect(position.legalMoves().contains(move("e5f6")))
        #expect(!position.legalMoves().contains(move("e5d6")))
        let after = position.applying(move("e5f6"))
        #expect(after[Square("f5")!] == nil)
        #expect(after[Square("f6")!] == Piece(color: .white, kind: .pawn))
    }

    @Test func enPassantThatExposesTheKingIsIllegal() throws {
        // After exd6 e.p. the white king would be in check from the rook along the fifth rank.
        let position = try Position(fen: "8/8/8/K2pP2r/8/8/8/4k3 w - d6 0 1")
        #expect(!position.legalMoves().contains(move("e5d6")))
    }

    @Test func promotionOffersFourPieces() throws {
        let position = try Position(fen: "8/P7/8/8/8/8/8/k1K5 w - - 0 1")
        let promotions = position.legalMoves().filter { $0.from == Square("a7") }
        #expect(Set(promotions.compactMap(\.promotion)) == [.queen, .rook, .bishop, .knight])
        #expect(promotions.count == 4)
        #expect(position.applying(move("a7a8n"))[Square("a8")!] == Piece(color: .white, kind: .knight))
    }

    @Test func castlingMovesKingAndRook() throws {
        let position = try Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        let short = position.applying(move("e1g1"))
        #expect(short.fen == "r3k2r/8/8/8/8/8/8/R4RK1 b kq - 1 1")
        let long = position.applying(move("e1c1"))
        #expect(long.fen == "r3k2r/8/8/8/8/8/8/2KR3R b kq - 1 1")
    }

    @Test func castlingThroughAnAttackedSquareIsIllegal() throws {
        let position = try Position(fen: "4k3/8/8/8/8/8/3r4/R3K3 w Q - 0 1")
        #expect(!position.legalMoves().contains(move("e1c1")))
    }

    @Test func castlingOutOfCheckIsIllegal() throws {
        let position = try Position(fen: "4k3/8/8/8/8/8/4r3/R3K3 w Q - 0 1")
        #expect(!position.legalMoves().contains(move("e1c1")))
    }

    @Test func longCastlingIsLegalWhenOnlyTheRookPathIsAttacked() throws {
        let position = try Position(fen: "4k3/8/8/8/8/8/1r6/R3K3 w Q - 0 1")
        #expect(position.legalMoves().contains(move("e1c1")))
    }

    @Test func castlingWithoutRightIsIllegal() throws {
        let position = try Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w Qkq - 0 1")
        #expect(!position.legalMoves().contains(move("e1g1")))
        #expect(position.legalMoves().contains(move("e1c1")))
    }

    @Test func capturingARookRemovesItsCastlingRight() throws {
        let position = try Position(fen: "4k2r/8/8/8/8/8/8/4K2R w Kk - 0 1")
        #expect(position.applying(move("h1h8")).fen == "4k2R/8/8/8/8/8/8/4K3 b - - 0 1")
    }

    @Test func doublePawnPushSetsEnPassantSquare() {
        let after = Position.start.applying(move("e2e4"))
        #expect(after.fen == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
    }

    @Test func pinnedPieceMayOnlyMoveAlongThePin() throws {
        let position = try Position(fen: "4k3/8/8/8/4r3/8/4R3/4K3 w - - 0 1")
        let rookTargets = Set(position.legalMoves().filter { $0.from == Square("e2") }.map(\.to.name))
        #expect(rookTargets == ["e3", "e4"])
    }

    @Test func checkIsDetected() throws {
        #expect(!Position.start.isInCheck)
        #expect(try Position(fen: "4k3/8/8/8/8/8/8/R3K2r w Q - 0 1").isInCheck)
    }
}
