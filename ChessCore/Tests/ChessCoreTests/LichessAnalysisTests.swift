import ChessCore
import Foundation
import Testing

@Suite struct LichessAnalysisTests {
    private func game(_ moves: String, from position: Position = .start) -> Game {
        var game = Game(position: position)
        for uci in moves.split(separator: " ") { game.make(Move(uci: String(uci))!) }
        return game
    }

    /// What Lichess makes of the URL: the path decoded, "_" and "+" read as spaces.
    private func pgnLichessReads(from url: URL) -> String {
        let path = url.absoluteString
            .replacingOccurrences(of: "https://lichess.org/analysis/pgn/", with: "")
            .components(separatedBy: "?")[0]
        return (path.removingPercentEncoding ?? "")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "+", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    @Test func movesBecomeAnAnalysisBoardURL() {
        let url = game("e2e4 e7e5 g1f3").lichessAnalysisURL()
        #expect(url.absoluteString == "https://lichess.org/analysis/pgn/e4_e5_Nf3")
    }

    @Test func checkAndMateSignsSurviveTheURL() {
        let url = game("f2f3 e7e5 g2g4 d8h4").lichessAnalysisURL()
        #expect(url.absoluteString == "https://lichess.org/analysis/pgn/f3_e5_g4_Qh4%23")
        #expect(pgnLichessReads(from: url) == "f3 e5 g4 Qh4#")
    }

    @Test func blackSeesTheBoardFromTheirSide() {
        let url = game("e2e4").lichessAnalysisURL(orientation: .black)
        #expect(url.absoluteString == "https://lichess.org/analysis/pgn/e4?color=black")
    }

    @Test func promotionAndCastlingAreKept() throws {
        let castling = game("e2e4 e7e5 g1f3 b8c6 f1c4 f8c5 e1g1").lichessAnalysisURL()
        #expect(pgnLichessReads(from: castling) == "e4 e5 Nf3 Nc6 Bc4 Bc5 O-O")
        let promotion = game("a7a8q", from: try Position(fen: "8/P7/8/8/8/8/8/k1K5 w - - 0 1")).lichessAnalysisURL()
        #expect(pgnLichessReads(from: promotion) == #"[FEN "8/P7/8/8/8/8/8/k1K5 w - - 0 1"] a8=Q#"#)
    }

    @Test func customStartingPositionTravelsAsFENTag() throws {
        let fen = "4k3/8/8/8/8/8/4P3/4K3 b - - 0 7"
        let url = game("e8d7 e2e4", from: try Position(fen: fen)).lichessAnalysisURL()
        #expect(pgnLichessReads(from: url) == #"[FEN "4k3/8/8/8/8/8/4P3/4K3 b - - 0 7"] Kd7 e4"#)
        #expect(!url.absoluteString.contains(" "))
    }

    @Test func gameWithoutMovesOpensAnEmptyAnalysisBoard() {
        #expect(Game().lichessAnalysisURL().absoluteString == "https://lichess.org/analysis")
        #expect(Game().lichessAnalysisURL(orientation: .black).absoluteString == "https://lichess.org/analysis?color=black")
    }
}
