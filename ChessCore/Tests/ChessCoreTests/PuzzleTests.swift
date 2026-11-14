import ChessCore
import Foundation
import Testing

@Suite struct PuzzleDecodingTests {
    @Test func lichessResponseBecomesAPuzzle() throws {
        let puzzle = try Puzzle(lichessJSON: Data(PuzzleFixtures.lichess.utf8))
        #expect(puzzle.source == .lichess)
        #expect(puzzle.id == "ioglh")
        #expect(puzzle.rating == 1947)
        #expect(puzzle.title == nil)
        #expect(puzzle.url == URL(string: "https://lichess.org/training/ioglh"))
        #expect(puzzle.lastMove == Move(uci: "f8f2"))
        #expect(puzzle.solution.map(\.uci) == ["g1f2", "c3d4", "f2g3"])
        #expect(puzzle.solverColor == .white)
        // Same pieces as the fen in the response; the position itself comes from replaying the game.
        #expect(puzzle.position.fen.hasPrefix("1k1r4/p5pp/1p6/4P3/8/P1q4P/Q1b2rP1/2R1R1K1 w "))
    }

    @Test func lichessPositionKeepsStateTheShortFENLacks() throws {
        // Replaying the game gives the real move number instead of the "0 1" placeholder.
        let puzzle = try Puzzle(lichessJSON: Data(PuzzleFixtures.lichess.utf8))
        #expect(puzzle.position.fullmoveNumber == 32)
    }

    @Test func lichessResponseWithoutFENAndLastMoveStillWorks() throws {
        var object = try JSONSerialization.jsonObject(with: Data(PuzzleFixtures.lichess.utf8)) as! [String: Any]
        var inner = object["puzzle"] as! [String: Any]
        inner["fen"] = nil
        inner["lastMove"] = nil
        object["puzzle"] = inner
        let puzzle = try Puzzle(lichessJSON: JSONSerialization.data(withJSONObject: object))
        #expect(puzzle.lastMove == Move(uci: "f8f2"))
        #expect(puzzle.position.fen.hasPrefix("1k1r4/p5pp/1p6/4P3/8/P1q4P/Q1b2rP1/2R1R1K1 w "))
    }

    @Test func lichessFENIsUsedWhenTheGameCannotBeReplayed() throws {
        var object = try JSONSerialization.jsonObject(with: Data(PuzzleFixtures.lichess.utf8)) as! [String: Any]
        var game = object["game"] as! [String: Any]
        game["pgn"] = "e4 e5 Qh7"
        object["game"] = game
        let puzzle = try Puzzle(lichessJSON: JSONSerialization.data(withJSONObject: object))
        #expect(puzzle.position.fen == "1k1r4/p5pp/1p6/4P3/8/P1q4P/Q1b2rP1/2R1R1K1 w - - 0 1")
        #expect(puzzle.lastMove == Move(uci: "f8f2"))
    }

    @Test func lichessCastlingWrittenAsKingTakesRookIsUnderstood() throws {
        let json = """
            {"game": {"pgn": "e4 e5 Nf3 Nc6 Bc4 Bc5"},
             "puzzle": {"id": "x", "rating": 1500, "plays": 1, "initialPly": 5, "solution": ["e1h1"], "themes": []}}
            """
        let puzzle = try Puzzle(lichessJSON: Data(json.utf8))
        #expect(puzzle.solution == [Move(uci: "e1g1")!])
    }

    @Test func lichessSolutionThatIsNotLegalIsRejected() {
        let json = """
            {"game": {"pgn": "e4 e5"},
             "puzzle": {"id": "x", "rating": 1500, "plays": 1, "initialPly": 1, "solution": ["a1a8"], "themes": []}}
            """
        #expect(throws: PuzzleError.invalidSolution) { try Puzzle(lichessJSON: Data(json.utf8)) }
    }

    @Test func lichessPuzzleWithoutSolutionIsRejected() {
        let json = """
            {"game": {"pgn": "e4 e5"},
             "puzzle": {"id": "x", "rating": 1500, "plays": 1, "initialPly": 1, "solution": [], "themes": []}}
            """
        #expect(throws: PuzzleError.invalidSolution) { try Puzzle(lichessJSON: Data(json.utf8)) }
    }

    @Test func chessComResponseBecomesAPuzzle() throws {
        let puzzle = try Puzzle(chessComJSON: Data(PuzzleFixtures.chessCom.utf8))
        #expect(puzzle.source == .chessCom)
        #expect(puzzle.id == "2026-11-11")
        #expect(puzzle.title == "Eviction Notice")
        #expect(puzzle.rating == nil)
        #expect(puzzle.url == URL(string: "https://www.chess.com/daily/2026-11-11"))
        #expect(puzzle.lastMove == nil)
        #expect(puzzle.position.fen == "6k1/4rb2/3b1R1Q/p6p/2pq3r/P2n2NP/1P4P1/5R1K w - - 0 1")
        #expect(puzzle.solution.map(\.uci) == ["f6g6", "f7g6", "f1f8"])
        #expect(puzzle.solverColor == .white)
    }

    @Test func chessComSolutionThatDoesNotFitThePositionIsRejected() {
        let json = #"{"title": "t", "url": "https://www.chess.com/daily/2026-01-01", "publish_time": 1, "fen": "4k3/8/8/8/8/8/8/4K3 w - - 0 1", "pgn": "[FEN \"4k3/8/8/8/8/8/8/4K3 w - - 0 1\"]\n\n1. Qh5 *"}"#
        #expect(throws: PuzzleError.invalidSolution) { try Puzzle(chessComJSON: Data(json.utf8)) }
    }

    @Test(arguments: ["", "{}", "[1, 2]", #"{"puzzle": {"id": 3}}"#])
    func malformedDataIsRejected(json: String) {
        #expect(throws: PuzzleError.malformed) { try Puzzle(lichessJSON: Data(json.utf8)) }
        #expect(throws: PuzzleError.malformed) { try Puzzle(chessComJSON: Data(json.utf8)) }
    }

    @Test func decodingDispatchesOnTheSource() throws {
        #expect(try Puzzle(source: .lichess, data: Data(PuzzleFixtures.lichess.utf8)).id == "ioglh")
        #expect(try Puzzle(source: .chessCom, data: Data(PuzzleFixtures.chessCom.utf8)).id == "2026-11-11")
    }
}

@Suite struct PuzzleSessionTests {
    private func sq(_ name: String) -> Square { Square(name)! }
    private func mv(_ uci: String) -> Move { Move(uci: uci)! }

    /// White to move. Solution: Rg6+ Bxg6, Rf8#.
    private func chessComSession() throws -> PuzzleSession {
        PuzzleSession(puzzle: try Puzzle(chessComJSON: Data(PuzzleFixtures.chessCom.utf8)))
    }

    /// White to move. Solution: Kxf2 Qd4+, Kg3.
    private func lichessSession() throws -> PuzzleSession {
        PuzzleSession(puzzle: try Puzzle(lichessJSON: Data(PuzzleFixtures.lichess.utf8)))
    }

    @Test func newSessionShowsThePuzzlePositionAndTheOpponentsLastMove() throws {
        let session = try lichessSession()
        #expect(session.position == session.puzzle.position)
        #expect(session.lastMove == mv("f8f2"))
        #expect(session.state == .solving)
        #expect(session.mistakes == 0)
    }

    @Test func correctMoveIsPlayedAndWaitsForTheReply() throws {
        var session = try chessComSession()
        let accepted = session.move(from: sq("f6"), to: sq("g6"))
        #expect(accepted)
        #expect(session.state == .awaitingReply)
        #expect(session.lastMove == mv("f6g6"))
        #expect(!session.canSelect(sq("f1")))
    }

    @Test func replyIsPlayedAndHandsTheMoveBack() throws {
        var session = try chessComSession()
        session.move(from: sq("f6"), to: sq("g6"))
        session.playReply()
        #expect(session.lastMove == mv("f7g6"))
        #expect(session.state == .solving)
        #expect(session.canSelect(sq("f1")))
    }

    @Test func playingReplyWhenNoneIsDueDoesNothing() throws {
        var session = try chessComSession()
        session.playReply()
        #expect(session.position == session.puzzle.position)
    }

    @Test func lastSolutionMoveSolvesThePuzzle() throws {
        var session = try chessComSession()
        session.move(from: sq("f6"), to: sq("g6"))
        session.playReply()
        session.move(from: sq("f1"), to: sq("f8"))
        #expect(session.state == .solved)
        #expect(!session.canSelect(sq("h6")))
    }

    @Test func wrongMoveIsNotPlayedAndCountsAsAMistake() throws {
        var session = try chessComSession()
        let accepted = session.move(from: sq("h6"), to: sq("h5"))
        #expect(!accepted)
        #expect(session.position == session.puzzle.position)
        #expect(session.state == .solving)
        #expect(session.mistakes == 1)
        #expect(session.lastAttemptFailed)
    }

    @Test func illegalMoveIsNotAMistake() throws {
        var session = try chessComSession()
        session.move(from: sq("f1"), to: sq("a8"))
        #expect(session.mistakes == 0)
        #expect(!session.lastAttemptFailed)
    }

    @Test func nextCorrectMoveClearsTheFailureMark() throws {
        var session = try chessComSession()
        session.move(from: sq("h6"), to: sq("h5"))
        session.move(from: sq("f6"), to: sq("g6"))
        #expect(!session.lastAttemptFailed)
        #expect(session.mistakes == 1)
    }

    @Test func selectingAPieceClearsTheFailureMark() throws {
        var session = try chessComSession()
        session.move(from: sq("h6"), to: sq("h5"))
        session.tap(sq("f6"))
        #expect(!session.lastAttemptFailed)
    }

    @Test func tappingWorksLikeOnTheGameBoard() throws {
        var session = try chessComSession()
        session.tap(sq("f6"))
        #expect(session.selectedSquare == sq("f6"))
        #expect(session.targetSquares.contains(sq("g6")))
        session.tap(sq("g6"))
        #expect(session.state == .awaitingReply)
        #expect(session.selectedSquare == nil)
    }

    @Test func onlyTheSolversPiecesCanBeSelected() throws {
        var session = try chessComSession()
        #expect(!session.canSelect(sq("g8")))
        session.tap(sq("g8"))
        #expect(session.selectedSquare == nil)
    }

    @Test func anyMateIsAcceptedInPlaceOfTheLastSolutionMoves() throws {
        // The listed line starts with Rb2, but Ra1 mates at once.
        let json = #"{"title": "t", "url": "https://www.chess.com/daily/2026-01-02", "publish_time": 1, "fen": "k7/2K5/8/8/8/8/8/1R6 w - - 0 1", "pgn": "[FEN \"k7/2K5/8/8/8/8/8/1R6 w - - 0 1\"]\n\n1. Rb2 Ka7 2. Ra2# *"}"#
        var session = PuzzleSession(puzzle: try Puzzle(chessComJSON: Data(json.utf8)))
        let accepted = session.move(from: sq("b1"), to: sq("a1"))
        #expect(accepted)
        #expect(session.state == .solved)
    }

    @Test func promotionWaitsForThePieceAndChecksItAgainstTheSolution() throws {
        let json = #"{"title": "t", "url": "https://www.chess.com/daily/2026-01-03", "publish_time": 1, "fen": "8/P7/8/8/8/8/7k/K7 w - - 0 1", "pgn": "[FEN \"8/P7/8/8/8/8/7k/K7 w - - 0 1\"]\n\n1. a8=R Kg3 2. Rg8+ *"}"#
        var session = PuzzleSession(puzzle: try Puzzle(chessComJSON: Data(json.utf8)))
        session.move(from: sq("a7"), to: sq("a8"))
        #expect(session.pendingPromotion == PendingPromotion(from: sq("a7"), to: sq("a8"), color: .white))
        session.promote(to: .queen)
        #expect(session.mistakes == 1)
        #expect(session.position == session.puzzle.position)
        session.move(from: sq("a7"), to: sq("a8"))
        session.promote(to: .rook)
        #expect(session.state == .awaitingReply)
    }

    @Test func illegalPromotionPieceIsIgnored() throws {
        let json = #"{"title": "t", "url": "https://www.chess.com/daily/2026-01-03", "publish_time": 1, "fen": "8/P7/8/8/8/8/7k/K7 w - - 0 1", "pgn": "[FEN \"8/P7/8/8/8/8/7k/K7 w - - 0 1\"]\n\n1. a8=R Kg3 2. Rg8+ *"}"#
        var session = PuzzleSession(puzzle: try Puzzle(chessComJSON: Data(json.utf8)))
        session.move(from: sq("a7"), to: sq("a8"))
        session.promote(to: .king)
        #expect(session.mistakes == 0)
        #expect(session.state == .solving)
        #expect(session.position == session.puzzle.position)
    }

    @Test func firstHintMarksThePieceAndTheSecondShowsTheMove() throws {
        var session = try chessComSession()
        #expect(session.hint == nil)
        session.showHint()
        #expect(session.hint == .piece(sq("f6")))
        session.showHint()
        #expect(session.hint == .move(mv("f6g6")))
        session.showHint()
        #expect(session.hint == .move(mv("f6g6")))
        #expect(session.hintsUsed)
    }

    @Test func hintDisappearsAfterTheMoveAndRefersToTheNextOne() throws {
        var session = try chessComSession()
        session.showHint()
        session.move(from: sq("f6"), to: sq("g6"))
        #expect(session.hint == nil)
        session.showHint()
        #expect(session.hint == nil)
        session.playReply()
        session.showHint()
        #expect(session.hint == .piece(sq("f1")))
    }

    @Test func restartBringsBackTheStartButKeepsNothingElse() throws {
        var session = try chessComSession()
        session.move(from: sq("h6"), to: sq("h5"))
        session.showHint()
        session.move(from: sq("f6"), to: sq("g6"))
        session.restart()
        #expect(session.position == session.puzzle.position)
        #expect(session.state == .solving)
        #expect(session.mistakes == 0)
        #expect(session.hint == nil)
        #expect(!session.hintsUsed)
    }

    @Test func lichessPuzzleIsSolvedMoveByMove() throws {
        var session = try lichessSession()
        session.move(from: sq("g1"), to: sq("f2"))
        session.playReply()
        #expect(session.lastMove == mv("c3d4"))
        session.move(from: sq("f2"), to: sq("g3"))
        #expect(session.state == .solved)
    }
}

@Suite struct SolvedPuzzlesTests {
    @Test func solvedPuzzleIsRemembered() throws {
        let puzzle = try Puzzle(chessComJSON: Data(PuzzleFixtures.chessCom.utf8))
        var solved = SolvedPuzzles()
        #expect(!solved.contains(puzzle))
        solved.insert(puzzle)
        #expect(solved.contains(puzzle))
    }

    @Test func puzzlesOfDifferentSourcesAreKeptApart() throws {
        var solved = SolvedPuzzles()
        solved.insert(try Puzzle(chessComJSON: Data(PuzzleFixtures.chessCom.utf8)))
        #expect(!solved.contains(try Puzzle(lichessJSON: Data(PuzzleFixtures.lichess.utf8))))
    }

    @Test func solvedListSurvivesJSONRoundTrip() throws {
        let puzzle = try Puzzle(lichessJSON: Data(PuzzleFixtures.lichess.utf8))
        var solved = SolvedPuzzles()
        solved.insert(puzzle)
        solved.insert(puzzle)
        let restored = try JSONDecoder().decode(SolvedPuzzles.self, from: JSONEncoder().encode(solved))
        #expect(restored == solved)
        #expect(restored.contains(puzzle))
    }

    @Test func onlyTheNewestEntriesAreKept() {
        var solved = SolvedPuzzles(limit: 3)
        for id in ["a", "b", "c", "d"] { solved.insert(source: .lichess, id: id) }
        #expect(!solved.contains(source: .lichess, id: "a"))
        #expect(solved.contains(source: .lichess, id: "b"))
        #expect(solved.contains(source: .lichess, id: "d"))
    }
}
