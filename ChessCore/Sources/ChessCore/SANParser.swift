extension Position {
    /// Reads a move in standard algebraic notation, e.g. "Nbd2", "exd5", "O-O" or "a8=Q#".
    ///
    /// Check marks and annotations ("+", "#", "!", "?") are ignored, and more disambiguation
    /// than necessary is accepted. Returns `nil` if the text does not name exactly one legal move.
    public func move(san: String) -> Move? {
        var text = Substring(san)
        while let last = text.last, "+#!?".contains(last) { text.removeLast() }
        guard !text.isEmpty else { return nil }
        let legal = legalMoves()

        if text == "O-O" || text == "0-0" || text == "O-O-O" || text == "0-0-0" {
            let targetFile = text.count == 3 ? 6 : 2
            return legal.first { isCastling($0) && $0.to.file == targetFile }
        }

        var promotion: PieceKind?
        if let last = text.last, last.isUppercase, text.count > 2 {
            guard let kind = PieceKind(letter: Character(last.lowercased())), Move.promotionKinds.contains(kind)
            else { return nil }
            promotion = kind
            text.removeLast()
            if text.last == "=" { text.removeLast() }
        }

        guard text.count >= 2, let target = Square(String(text.suffix(2))) else { return nil }
        text.removeLast(2)

        var kind = PieceKind.pawn
        if let first = text.first, first.isUppercase {
            guard let named = PieceKind(letter: Character(first.lowercased())), named != .pawn else { return nil }
            kind = named
            text.removeFirst()
        }

        var file: Int?
        var rank: Int?
        for character in text where character != "x" {
            guard let value = character.asciiValue else { return nil }
            switch value {
            case 97...104 where file == nil && rank == nil: file = Int(value) - 97
            case 49...56 where rank == nil: rank = Int(value) - 49
            default: return nil
            }
        }

        let matches = legal.filter { move in
            move.to == target
                && move.promotion == promotion
                && mask(of: kind) & move.from.bit != 0
                && (file == nil || move.from.file == file)
                && (rank == nil || move.from.rank == rank)
        }
        return matches.count == 1 ? matches[0] : nil
    }
}
