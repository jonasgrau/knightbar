import ChessCore
import Foundation
import Testing

@Suite struct ResignationTests {
    @Test func resigningEndsTheGameInFavourOfTheOpponent() {
        var game = Game()
        game.make(Move(uci: "e2e4")!)
        game.resign(.black)
        #expect(game.status == .resigned(winner: .white))
        #expect(game.legalMoves.isEmpty)
        #expect(game.pgnResult == "1-0")
        #expect(game.pgn().hasSuffix("\n1. e4 1-0\n"))
    }

    @Test func resigningAFinishedGameChangesNothing() throws {
        var game = try Game(position: Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
        game.resign(.black)
        #expect(game.status == .stalemate)
    }

    @Test func undoAfterResigningOnlyWithdrawsTheResignation() {
        var game = Game()
        game.make(Move(uci: "e2e4")!)
        game.resign(.white)
        game.undo()
        #expect(game.status == .ongoing)
        #expect(game.moves.count == 1)
    }
}

@Suite struct ComputerMatchSessionTests {
    private func sq(_ name: String) -> Square { Square(name)! }
    private func mv(_ uci: String) -> Move { Move(uci: uci)! }

    @Test func onlyTheHumanColourCanBeSelected() {
        var session = BoardSession(humanColors: [.black])
        #expect(!session.canSelect(sq("e2")))
        #expect(session.isEngineTurn)
        session.tap(sq("e2"))
        #expect(session.selectedSquare == nil)
    }

    @Test func humanCannotMoveTheEnginesPieces() {
        var session = BoardSession(humanColors: [.black])
        let moved = session.move(from: sq("e2"), to: sq("e4"))
        #expect(!moved)
        #expect(session.game.moves.isEmpty)
    }

    @Test func engineMoveIsPlayedAndHandsTheTurnToTheHuman() {
        var session = BoardSession(humanColors: [.black])
        let played = session.playEngineMove(mv("e2e4"))
        #expect(played)
        #expect(!session.isEngineTurn)
        #expect(session.canSelect(sq("e7")))
    }

    @Test func engineMoveIsRejectedWhenItIsTheHumansTurn() {
        var session = BoardSession(humanColors: [.white])
        let played = session.playEngineMove(mv("e2e4"))
        #expect(!played)
        #expect(session.game.moves.isEmpty)
    }

    @Test func illegalEngineMoveIsRejected() {
        var session = BoardSession(humanColors: [.black])
        let played = session.playEngineMove(mv("e2e5"))
        #expect(!played)
    }

    @Test func twoPlayerSessionHasNoEngineTurn() {
        var session = BoardSession()
        #expect(!session.isEngineTurn)
        session.move(from: sq("e2"), to: sq("e4"))
        #expect(!session.isEngineTurn)
        #expect(session.canSelect(sq("e7")))
    }

    @Test func noEngineTurnAfterTheGameEnded() throws {
        let game = try Game(position: Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
        #expect(!BoardSession(game: game, humanColors: [.white]).isEngineTurn)
    }

    @Test func undoTakesBackTheHumanMoveTogetherWithTheEngineReply() {
        var session = BoardSession(humanColors: [.white])
        session.move(from: sq("e2"), to: sq("e4"))
        session.playEngineMove(mv("e7e5"))
        session.move(from: sq("g1"), to: sq("f3"))
        session.playEngineMove(mv("b8c6"))
        session.undo()
        #expect(session.game.moves == [mv("e2e4"), mv("e7e5")])
    }

    @Test func undoWhileTheEngineThinksTakesBackOnlyTheHumanMove() {
        var session = BoardSession(humanColors: [.white])
        session.move(from: sq("e2"), to: sq("e4"))
        session.undo()
        #expect(session.game.moves.isEmpty)
    }

    @Test func undoIsUnavailableBeforeTheHumanHasMoved() {
        var session = BoardSession(humanColors: [.black])
        #expect(!session.canUndo)
        session.playEngineMove(mv("e2e4"))
        #expect(!session.canUndo)
        session.undo()
        #expect(session.game.moves == [mv("e2e4")])
        session.move(from: sq("e7"), to: sq("e5"))
        #expect(session.canUndo)
    }

    @Test func undoInATwoPlayerSessionTakesBackASingleMove() {
        var session = BoardSession()
        session.move(from: sq("e2"), to: sq("e4"))
        session.move(from: sq("e7"), to: sq("e5"))
        #expect(session.canUndo)
        session.undo()
        #expect(session.game.moves == [mv("e2e4")])
    }

    @Test func humanResignsTheirOwnColourAgainstTheComputer() {
        var session = BoardSession(humanColors: [.black])
        session.playEngineMove(mv("e2e4"))
        session.resign()
        #expect(session.game.status == .resigned(winner: .white))
    }

    @Test func humanCanResignWhileTheEngineIsThinking() {
        var session = BoardSession(humanColors: [.white])
        session.move(from: sq("e2"), to: sq("e4"))
        session.resign()
        #expect(session.game.status == .resigned(winner: .black))
        #expect(!session.isEngineTurn)
    }

    @Test func sideToMoveResignsInATwoPlayerSession() {
        var session = BoardSession()
        session.move(from: sq("e2"), to: sq("e4"))
        session.resign()
        #expect(session.game.status == .resigned(winner: .white))
    }

    @Test func undoWithdrawsAResignation() {
        var session = BoardSession(humanColors: [.white])
        session.move(from: sq("e2"), to: sq("e4"))
        session.playEngineMove(mv("e7e5"))
        session.resign()
        #expect(session.canUndo)
        session.undo()
        #expect(session.game.status == .ongoing)
        #expect(session.game.moves.count == 2)
    }

    @Test func newGameCanChangeWhoIsHuman() {
        var session = BoardSession(humanColors: [.white])
        session.move(from: sq("e2"), to: sq("e4"))
        session.newGame(humanColors: [.black])
        #expect(session.game.moves.isEmpty)
        #expect(session.isEngineTurn)
    }

    @Test func humanColoursCanChangeDuringAGame() {
        var session = BoardSession()
        session.move(from: sq("e2"), to: sq("e4"))
        session.tap(sq("e7"))
        session.humanColors = [.white]
        #expect(session.isEngineTurn)
        #expect(session.selectedSquare == nil)
    }
}

@Suite struct MatchSettingsTests {
    @Test func defaultsAreAMidLevelComputerOpponentWithWhiteForTheHuman() {
        let settings = MatchSettings()
        #expect(settings.opponent == .computer)
        #expect(settings.colorChoice == .white)
        #expect(settings.strength.level == 3)
        #expect(settings.moveTime == 1)
    }

    @Test func humanColoursFollowOpponentAndPlayerColour() {
        var settings = MatchSettings()
        #expect(settings.humanColors(playingAs: .black) == [.black])
        settings.opponent = .human
        #expect(settings.humanColors(playingAs: .black) == [.white, .black])
    }

    @Test func fixedColourChoiceResolvesToItself() {
        #expect(MatchSettings.ColorChoice.white.resolved() == .white)
        #expect(MatchSettings.ColorChoice.black.resolved() == .black)
    }

    @Test func randomColourChoiceUsesTheGivenGenerator() {
        struct Fixed: RandomNumberGenerator {
            var value: UInt64
            mutating func next() -> UInt64 { value }
        }
        var low = Fixed(value: 0), high = Fixed(value: .max)
        let colors: Set = [MatchSettings.ColorChoice.random.resolved(using: &low),
                           MatchSettings.ColorChoice.random.resolved(using: &high)]
        #expect(colors == [.white, .black])
    }

    @Test func settingsSurviveJSONRoundTrip() throws {
        var settings = MatchSettings()
        settings.opponent = .human
        settings.colorChoice = .random
        settings.strength = EngineStrength(level: 7)
        settings.moveTime = 2
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(MatchSettings.self, from: data) == settings)
    }
}

@Suite struct SavedGameTests {
    private func playedSession() -> BoardSession {
        var session = BoardSession(humanColors: [.black])
        session.playEngineMove(Move(uci: "e2e4")!)
        session.move(from: Square("e7")!, to: Square("e5")!)
        session.playEngineMove(Move(uci: "g1f3")!)
        return session
    }

    @Test func savedGameRestoresMovesAndPlayerColour() throws {
        let saved = SavedGame(game: playedSession().game, playerColor: .black)
        let data = try JSONEncoder().encode(saved)
        let restored = try JSONDecoder().decode(SavedGame.self, from: data)
        #expect(restored.playerColor == .black)
        let game = try restored.restoredGame()
        #expect(game.moves.map(\.uci) == ["e2e4", "e7e5", "g1f3"])
        #expect(game.position == playedSession().game.position)
        #expect(game.status == .ongoing)
    }

    @Test func savedGameKeepsACustomStartingPosition() throws {
        let fen = "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1"
        var game = Game(position: try Position(fen: fen))
        game.make(Move(uci: "e2e4")!)
        let restored = try SavedGame(game: game, playerColor: .white).restoredGame()
        #expect(restored.startPosition.fen == fen)
        #expect(restored.moves == [Move(uci: "e2e4")!])
    }

    @Test func savedGameKeepsAResignation() throws {
        var game = Game()
        game.make(Move(uci: "e2e4")!)
        game.resign(.black)
        let restored = try SavedGame(game: game, playerColor: .black).restoredGame()
        #expect(restored.status == .resigned(winner: .white))
    }

    @Test func savedGameWithAnIllegalMoveIsRejected() throws {
        let json = #"{"startFEN":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","moves":["e2e5"],"playerColor":"white"}"#
        let saved = try JSONDecoder().decode(SavedGame.self, from: Data(json.utf8))
        #expect(throws: SavedGameError.self) { try saved.restoredGame() }
    }

    @Test func savedGameWithABrokenFENIsRejected() throws {
        let json = #"{"startFEN":"nonsense","moves":[],"playerColor":"white"}"#
        let saved = try JSONDecoder().decode(SavedGame.self, from: Data(json.utf8))
        #expect(throws: SavedGameError.self) { try saved.restoredGame() }
    }

    @Test func storeWritesAndReadsTheGameFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "chesscore-tests-\(UUID().uuidString)/nested/game.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent()) }
        let store = SavedGameStore(fileURL: url)
        #expect(try store.load() == nil)
        let saved = SavedGame(game: playedSession().game, playerColor: .black)
        try store.save(saved)
        #expect(try store.load() == saved)
    }

    @Test func storeReportsACorruptFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "chesscore-tests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{not json".utf8).write(to: url)
        #expect(throws: (any Error).self) { try SavedGameStore(fileURL: url).load() }
    }
}
