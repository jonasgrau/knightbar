public enum PieceColor: String, Hashable, Sendable, CaseIterable, Codable {
    case white, black

    public var opposite: PieceColor { self == .white ? .black : .white }
}

public enum PieceKind: Hashable, Sendable, CaseIterable {
    case pawn, knight, bishop, rook, queen, king

    /// Lowercase letter as used in FEN and UCI ("p", "n", "b", "r", "q", "k").
    public var letter: Character {
        switch self {
        case .pawn: "p"
        case .knight: "n"
        case .bishop: "b"
        case .rook: "r"
        case .queen: "q"
        case .king: "k"
        }
    }

    public init?(letter: Character) {
        guard let kind = PieceKind.allCases.first(where: { $0.letter == letter }) else { return nil }
        self = kind
    }
}

public struct Piece: Hashable, Sendable {
    public var color: PieceColor
    public var kind: PieceKind

    public init(color: PieceColor, kind: PieceKind) {
        self.color = color
        self.kind = kind
    }

    /// FEN character: uppercase for white, lowercase for black.
    public var fenCharacter: Character {
        color == .white ? Character(kind.letter.uppercased()) : kind.letter
    }

    public init?(fenCharacter: Character) {
        guard let kind = PieceKind(letter: Character(fenCharacter.lowercased())) else { return nil }
        self.init(color: fenCharacter.isUppercase ? .white : .black, kind: kind)
    }
}
