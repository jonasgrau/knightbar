import Foundation

extension Game {
    /// A link that opens this game on the Lichess analysis board.
    ///
    /// The moves travel in the link itself, as Lichess documents for analysing a line: nothing is
    /// uploaded and no game is created on Lichess. Lichess reads "_" and "+" in the path as spaces,
    /// so check marks are dropped there, which does not change the moves.
    public func lichessAnalysisURL(orientation: PieceColor = .white) -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-=+")

        var tokens = sanMoves
        if startPosition != .start {
            tokens.insert("[FEN \"\(startPosition.fen)\"]", at: 0)
        }
        let pgn = tokens
            .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }
            .joined(separator: "_")
            // Spaces inside the FEN tag become "_" as well; Lichess turns them back into spaces.
            .replacingOccurrences(of: "%20", with: "_")

        var link = pgn.isEmpty ? "https://lichess.org/analysis" : "https://lichess.org/analysis/pgn/\(pgn)"
        if orientation == .black { link += "?color=black" }
        return URL(string: link)!
    }
}
