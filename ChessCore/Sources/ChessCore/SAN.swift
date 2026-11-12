extension Position {
    /// Writes a legal move in standard algebraic notation, e.g. "Nbd2", "exd5", "O-O" or "a8=Q#".
    public func san(for move: Move) -> String {
        guard let piece = self[move.from] else { return move.uci }
        var text: String

        if isCastling(move) {
            text = move.to.file == 6 ? "O-O" : "O-O-O"
        } else {
            let capture = isCapture(move)
            let fileName = String(move.from.name.prefix(1))
            if piece.kind == .pawn {
                text = capture ? fileName + "x" : ""
            } else {
                text = piece.kind.letter.uppercased() + disambiguation(for: move, kind: piece.kind)
                if capture { text += "x" }
            }
            text += move.to.name
            if let promotion = move.promotion {
                text += "=" + promotion.letter.uppercased()
            }
        }

        let after = applying(move)
        if after.isInCheck {
            text += after.legalMoves().isEmpty ? "#" : "+"
        }
        return text
    }

    /// Disambiguation when several pieces of the same kind can reach the square: the file first,
    /// otherwise the rank, and both if needed.
    private func disambiguation(for move: Move, kind: PieceKind) -> String {
        let rivals = legalMoves()
            .filter { $0.to == move.to && $0.from != move.from && mask(of: kind) & $0.from.bit != 0 }
            .map(\.from)
        guard !rivals.isEmpty else { return "" }
        let name = move.from.name
        if !rivals.contains(where: { $0.file == move.from.file }) { return String(name.prefix(1)) }
        if !rivals.contains(where: { $0.rank == move.from.rank }) { return String(name.suffix(1)) }
        return name
    }
}
