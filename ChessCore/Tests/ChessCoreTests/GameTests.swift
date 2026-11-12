import Testing
import ChessCore

@Suite struct GameTests {
    private func play(_ moves: String, from fen: String? = nil) throws -> Game {
        var game = try fen.map { Game(position: try Position(fen: $0)) } ?? Game()
        for uci in moves.split(separator: " ") {
            do { let made = game.make(Move(uci: String(uci))!); #expect(made, "move \(uci) should be legal") }
        }
        return game
    }

    @Test func newGameIsOngoingInStartPosition() {
        let game = Game()
        #expect(game.status == .ongoing)
        #expect(game.position == .start)
        #expect(game.moves.isEmpty)
    }

    @Test func foolsMateIsCheckmateForBlack() throws {
        let game = try play("f2f3 e7e5 g2g4 d8h4")
        #expect(game.status == .checkmate(winner: .black))
        #expect(game.legalMoves.isEmpty)
    }

    @Test func stalemateIsDetected() throws {
        let game = try Game(position: Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
        #expect(game.status == .stalemate)
    }

    @Test func hundredHalfmovesWithoutProgressIsADraw() throws {
        var game = try Game(position: Position(fen: "8/8/8/8/8/5k2/8/4K2R w - - 98 80"))
        do { let made = game.make(Move(uci: "h1h2")!); #expect(made) }
        #expect(game.status == .ongoing)
        do { let made = game.make(Move(uci: "f3g3")!); #expect(made) }
        #expect(game.status == .draw(.fiftyMoves))
    }

    @Test func checkmateOnTheHundredthHalfmoveStillWins() throws {
        var game = try Game(position: Position(fen: "7k/8/6K1/8/8/8/8/R7 w - - 99 80"))
        do { let made = game.make(Move(uci: "a1a8")!); #expect(made) }
        #expect(game.status == .checkmate(winner: .white))
    }

    @Test func thirdOccurrenceOfAPositionIsADraw() throws {
        var game = try play("g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1")
        #expect(game.status == .ongoing)
        do { let made = game.make(Move(uci: "f6g8")!); #expect(made) }
        #expect(game.status == .draw(.threefoldRepetition))
    }

    @Test func undoneMovesDoNotCountTowardsRepetition() throws {
        var game = Game()
        for _ in 0..<3 {
            do { let made = game.make(Move(uci: "e2e4")!); #expect(made) }
            game.undo()
        }
        #expect(game.status == .ongoing)
        #expect(game.position == .start)
    }

    @Test(arguments: [
        "8/8/4k3/8/8/3K4/8/8 w - - 0 1",        // king against king
        "8/8/4k3/8/8/3K4/8/6N1 w - - 0 1",      // king and knight
        "8/8/4k3/8/8/3K4/8/5B2 b - - 0 1",      // king and bishop
        "8/8/b3k3/8/3K4/8/8/5B2 w - - 0 1",     // same-coloured bishops
    ])
    func deadPositionIsADraw(fen: String) throws {
        #expect(try Game(position: Position(fen: fen)).status == .draw(.insufficientMaterial))
    }

    @Test(arguments: [
        "8/8/4k3/8/8/3K4/8/7R w - - 0 1",       // rook
        "8/8/4k3/8/8/3K4/4P3/8 w - - 0 1",      // pawn
        "7b/8/4k3/8/8/3K4/8/5B2 w - - 0 1",     // opposite-coloured bishops
        "8/8/4k3/8/8/3K4/8/5NN1 w - - 0 1",     // two knights
    ])
    func positionWithMatingMaterialIsOngoing(fen: String) throws {
        #expect(try Game(position: Position(fen: fen)).status == .ongoing)
    }

    @Test func illegalMoveIsRejectedAndLeavesTheGameUnchanged() {
        var game = Game()
        do { let made = game.make(Move(uci: "e2e5")!); #expect(!made) }
        #expect(game.position == .start)
        #expect(game.moves.isEmpty)
    }

    @Test func pawnMoveToLastRankWithoutPromotionPieceIsRejected() throws {
        var game = try Game(position: Position(fen: "8/P7/8/8/8/8/8/k1K5 w - - 0 1"))
        do { let made = game.make(Move(uci: "a7a8")!); #expect(!made) }
        do { let made = game.make(Move(uci: "a7a8q")!); #expect(made) }
    }

    @Test func noMovesAreAcceptedAfterTheGameEnded() throws {
        var game = try play("f2f3 e7e5 g2g4 d8h4")
        do { let made = game.make(Move(uci: "a2a3")!); #expect(!made) }
    }

    @Test func undoRestoresThePreviousPositionAndStatus() throws {
        var game = try play("f2f3 e7e5 g2g4 d8h4")
        game.undo()
        #expect(game.status == .ongoing)
        #expect(game.moves.count == 3)
        #expect(game.position.sideToMove == .black)
        #expect(game.lastMove == Move(uci: "g2g4"))
    }

    @Test func undoOnANewGameDoesNothing() {
        var game = Game()
        game.undo()
        #expect(game.position == .start)
    }
}
