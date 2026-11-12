import Testing
import ChessCore

@Suite struct BoardSessionTests {
    private func sq(_ name: String) -> Square { Square(name)! }

    private func session(fen: String) throws -> BoardSession {
        BoardSession(game: Game(position: try Position(fen: fen)))
    }

    @Test func tappingOwnPieceSelectsItAndShowsItsTargets() {
        var session = BoardSession()
        session.tap(sq("e2"))
        #expect(session.selectedSquare == sq("e2"))
        #expect(Set(session.targetSquares) == [sq("e3"), sq("e4")])
    }

    @Test func tappingATargetMakesTheMoveAndClearsTheSelection() {
        var session = BoardSession()
        session.tap(sq("e2"))
        session.tap(sq("e4"))
        #expect(session.game.moves == [Move(uci: "e2e4")!])
        #expect(session.selectedSquare == nil)
        #expect(session.targetSquares.isEmpty)
    }

    @Test func tappingOpponentPieceOrEmptySquareSelectsNothing() {
        var session = BoardSession()
        session.tap(sq("e7"))
        #expect(session.selectedSquare == nil)
        session.tap(sq("e4"))
        #expect(session.selectedSquare == nil)
    }

    @Test func tappingTheSelectedPieceAgainDeselectsIt() {
        var session = BoardSession()
        session.tap(sq("e2"))
        session.tap(sq("e2"))
        #expect(session.selectedSquare == nil)
    }

    @Test func tappingAnotherOwnPieceSwitchesTheSelection() {
        var session = BoardSession()
        session.tap(sq("e2"))
        session.tap(sq("g1"))
        #expect(session.selectedSquare == sq("g1"))
        #expect(session.game.moves.isEmpty)
    }

    @Test func tappingASquareThePieceCannotReachClearsTheSelection() {
        var session = BoardSession()
        session.tap(sq("e2"))
        session.tap(sq("e5"))
        #expect(session.selectedSquare == nil)
        #expect(session.game.moves.isEmpty)
    }

    @Test func selectingKeepsAnAlreadySelectedPieceSelected() {
        var session = BoardSession()
        session.select(sq("e2"))
        session.select(sq("e2"))
        #expect(session.selectedSquare == sq("e2"))
    }

    @Test func selectingAPieceThatMayNotMoveIsRefused() {
        var session = BoardSession()
        do { let done = session.select(sq("e7")); #expect(!done) }
        do { let done = session.select(sq("e4")); #expect(!done) }
        #expect(session.selectedSquare == nil)
    }

    @Test func legalDropMakesTheMove() {
        var session = BoardSession()
        session.select(sq("g1"))
        do { let done = session.move(from: sq("g1"), to: sq("f3")); #expect(done) }
        #expect(session.game.moves == [Move(uci: "g1f3")!])
        #expect(session.selectedSquare == nil)
    }

    @Test func illegalDropChangesNothingAndClearsTheSelection() {
        var session = BoardSession()
        session.select(sq("g1"))
        do { let done = session.move(from: sq("g1"), to: sq("g3")); #expect(!done) }
        #expect(session.game.moves.isEmpty)
        #expect(session.selectedSquare == nil)
    }

    @Test func pawnReachingTheLastRankWaitsForAPromotionChoice() throws {
        var session = try session(fen: "8/P7/8/8/8/8/8/k1K5 w - - 0 1")
        session.tap(sq("a7"))
        session.tap(sq("a8"))
        #expect(session.pendingPromotion == PendingPromotion(from: sq("a7"), to: sq("a8"), color: .white))
        #expect(session.game.moves.isEmpty)

        session.promote(to: .rook)
        #expect(session.game.moves == [Move(uci: "a7a8r")!])
        #expect(session.pendingPromotion == nil)
    }

    @Test func cancelledPromotionLeavesThePawnInPlace() throws {
        var session = try session(fen: "8/P7/8/8/8/8/8/k1K5 w - - 0 1")
        do { let done = session.move(from: sq("a7"), to: sq("a8")); #expect(!done) }
        session.cancelPromotion()
        #expect(session.pendingPromotion == nil)
        #expect(session.game.moves.isEmpty)
        #expect(session.selectedSquare == nil)
    }

    @Test func tapsAreIgnoredWhileAPromotionIsPending() throws {
        var session = try session(fen: "8/P7/8/8/8/8/8/k1K5 w - - 0 1")
        session.move(from: sq("a7"), to: sq("a8"))
        session.tap(sq("c1"))
        #expect(session.selectedSquare == nil)
        #expect(session.pendingPromotion != nil)
    }

    @Test func nothingCanBeSelectedAfterTheGameEnded() throws {
        var session = try session(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        session.tap(sq("h8"))
        #expect(session.selectedSquare == nil)
    }

    @Test func undoTakesBackTheLastMoveAndClearsInputState() {
        var session = BoardSession()
        session.move(from: sq("e2"), to: sq("e4"))
        session.tap(sq("e7"))
        session.undo()
        #expect(session.game.moves.isEmpty)
        #expect(session.selectedSquare == nil)
    }

    @Test func newGameResetsEverything() {
        var session = BoardSession()
        session.move(from: sq("e2"), to: sq("e4"))
        session.tap(sq("e7"))
        session.newGame()
        #expect(session.game.position == .start)
        #expect(session.game.moves.isEmpty)
        #expect(session.selectedSquare == nil)
    }

    @Test func checkedKingSquareIsReported() throws {
        #expect(BoardSession().checkedKingSquare == nil)
        #expect(try session(fen: "4k3/8/8/8/8/8/8/R3K2r w Q - 0 1").checkedKingSquare == sq("e1"))
    }
}
