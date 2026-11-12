public struct CastlingRights: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let whiteKingside = CastlingRights(rawValue: 1)
    public static let whiteQueenside = CastlingRights(rawValue: 2)
    public static let blackKingside = CastlingRights(rawValue: 4)
    public static let blackQueenside = CastlingRights(rawValue: 8)
    public static let all: CastlingRights = [.whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside]
}

/// A complete chess position, as a FEN string describes it.
///
/// The pieces are stored in eight bit masks (two colours, six piece kinds), which keeps
/// the struct small and copyable without heap allocation.
public struct Position: Hashable, Sendable {
    var white: UInt64 = 0
    var black: UInt64 = 0
    var pawns: UInt64 = 0
    var knights: UInt64 = 0
    var bishops: UInt64 = 0
    var rooks: UInt64 = 0
    var queens: UInt64 = 0
    var kings: UInt64 = 0

    public internal(set) var sideToMove: PieceColor = .white
    public internal(set) var castlingRights: CastlingRights = []
    /// Square behind a pawn that has just made a double step.
    public internal(set) var enPassantSquare: Square?
    /// Halfmoves since the last pawn move or capture (for the fifty-move rule).
    public internal(set) var halfmoveClock: Int = 0
    public internal(set) var fullmoveNumber: Int = 1

    init() {}

    public static let start = try! Position(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")

    public subscript(square: Square) -> Piece? {
        let bit = square.bit
        guard occupied & bit != 0 else { return nil }
        let kind: PieceKind =
            if pawns & bit != 0 { .pawn }
            else if knights & bit != 0 { .knight }
            else if bishops & bit != 0 { .bishop }
            else if rooks & bit != 0 { .rook }
            else if queens & bit != 0 { .queen }
            else { .king }
        return Piece(color: white & bit != 0 ? .white : .black, kind: kind)
    }

    /// All occupied squares with their pieces, from a1 to h8.
    public var pieces: [(square: Square, piece: Piece)] {
        Square.all.compactMap { square in self[square].map { (square, $0) } }
    }

    public func kingSquare(of color: PieceColor) -> Square? {
        let mask = kings & self.mask(of: color)
        return mask == 0 ? nil : Square(index: mask.trailingZeroBitCount)
    }

    // MARK: - Internal access

    var occupied: UInt64 { white | black }

    func mask(of color: PieceColor) -> UInt64 { color == .white ? white : black }

    func mask(of kind: PieceKind) -> UInt64 {
        switch kind {
        case .pawn: pawns
        case .knight: knights
        case .bishop: bishops
        case .rook: rooks
        case .queen: queens
        case .king: kings
        }
    }

    mutating func put(_ piece: Piece, at square: Square) {
        remove(at: square)
        let bit = square.bit
        if piece.color == .white { white |= bit } else { black |= bit }
        switch piece.kind {
        case .pawn: pawns |= bit
        case .knight: knights |= bit
        case .bishop: bishops |= bit
        case .rook: rooks |= bit
        case .queen: queens |= bit
        case .king: kings |= bit
        }
    }

    mutating func remove(at square: Square) {
        let keep = ~square.bit
        white &= keep
        black &= keep
        pawns &= keep
        knights &= keep
        bishops &= keep
        rooks &= keep
        queens &= keep
        kings &= keep
    }
}
