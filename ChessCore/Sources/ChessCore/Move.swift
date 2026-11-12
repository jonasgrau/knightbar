public struct Move: Hashable, Sendable {
    public var from: Square
    public var to: Square
    /// Set when a pawn reaches the last rank.
    public var promotion: PieceKind?

    public init(from: Square, to: Square, promotion: PieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    /// Reads UCI notation, e.g. "e2e4" or "e7e8q".
    public init?(uci: String) {
        let characters = Array(uci)
        guard characters.count == 4 || characters.count == 5,
              let from = Square(String(characters[0...1])),
              let to = Square(String(characters[2...3]))
        else { return nil }
        var promotion: PieceKind?
        if characters.count == 5 {
            guard let kind = PieceKind(letter: characters[4]), Move.promotionKinds.contains(kind) else { return nil }
            promotion = kind
        }
        self.init(from: from, to: to, promotion: promotion)
    }

    public var uci: String {
        from.name + to.name + (promotion.map { String($0.letter) } ?? "")
    }

    public static let promotionKinds: [PieceKind] = [.queen, .rook, .bishop, .knight]
}

extension Position {
    /// Reads a legal move in UCI notation. Castling may also be written as the king moving
    /// onto its own rook ("e1h1"), as Lichess does in some places.
    public func move(uci: String) -> Move? {
        guard var move = Move(uci: uci) else { return nil }
        if isLegal(move) { return move }
        guard let king = self[move.from], king.kind == .king,
              self[move.to] == Piece(color: king.color, kind: .rook)
        else { return nil }
        move.to = Square(file: move.to.file > move.from.file ? 6 : 2, rank: move.from.rank)
        return isLegal(move) ? move : nil
    }
}

extension Move: CustomStringConvertible {
    public var description: String { uci }
}
