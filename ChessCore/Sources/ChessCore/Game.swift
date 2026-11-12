public enum DrawReason: Hashable, Sendable {
    case fiftyMoves
    case threefoldRepetition
    case insufficientMaterial
}

public enum GameStatus: Hashable, Sendable {
    case ongoing
    case checkmate(winner: PieceColor)
    case stalemate
    case draw(DrawReason)
    case resigned(winner: PieceColor)

    public var isOver: Bool { self != .ongoing }
}

/// A game: the starting position, the moves played and the resulting status.
public struct Game: Sendable {
    public let startPosition: Position
    public private(set) var moves: [Move] = []
    /// Every position of the game. The first is the starting position, the last the current one.
    public private(set) var positions: [Position]
    public private(set) var status: GameStatus = .ongoing
    /// The side that gave up, if any.
    public private(set) var resignedBy: PieceColor?

    /// Whether the fifty-move rule, threefold repetition and insufficient material end the game
    /// by themselves. Switched off for games whose result is decided elsewhere.
    public let automaticDraws: Bool

    public init(position: Position = .start, automaticDraws: Bool = true) {
        startPosition = position
        self.automaticDraws = automaticDraws
        positions = [position]
        status = computeStatus()
    }

    public var position: Position { positions[positions.count - 1] }
    public var lastMove: Move? { moves.last }

    /// Legal moves in the current position. Empty once the game is over.
    public var legalMoves: [Move] {
        status.isOver ? [] : position.legalMoves()
    }

    /// Plays `move` if it is legal and the game is still in progress.
    @discardableResult
    public mutating func make(_ move: Move) -> Bool {
        guard !status.isOver, position.isLegal(move) else { return false }
        moves.append(move)
        positions.append(position.applying(move))
        status = computeStatus()
        return true
    }

    /// Ends the game as a loss for `color`. Does nothing if the game is already over.
    public mutating func resign(_ color: PieceColor) {
        guard !status.isOver else { return }
        resignedBy = color
        status = computeStatus()
    }

    /// Takes back the last move. After a resignation it only withdraws the resignation.
    public mutating func undo() {
        if resignedBy != nil {
            resignedBy = nil
            status = computeStatus()
            return
        }
        guard !moves.isEmpty else { return }
        moves.removeLast()
        positions.removeLast()
        status = computeStatus()
    }

    private func computeStatus() -> GameStatus {
        if let resignedBy { return .resigned(winner: resignedBy.opposite) }
        let current = position
        if current.legalMoves().isEmpty {
            return current.isInCheck ? .checkmate(winner: current.sideToMove.opposite) : .stalemate
        }
        guard automaticDraws else { return .ongoing }
        if current.hasInsufficientMaterial { return .draw(.insufficientMaterial) }
        if current.halfmoveClock >= 100 { return .draw(.fiftyMoves) }
        let key = current.repetitionKey
        if positions.count(where: { $0.repetitionKey == key }) >= 3 { return .draw(.threefoldRepetition) }
        return .ongoing
    }
}

extension Position {
    /// The position without its counters. Two positions count as repeated when these keys are equal.
    ///
    /// The en passant square only counts if capturing there is actually possible.
    var repetitionKey: Position {
        var key = self
        key.halfmoveClock = 0
        key.fullmoveNumber = 1
        if enPassantSquare != nil, !legalMoves().contains(where: isEnPassant) {
            key.enPassantSquare = nil
        }
        return key
    }

    /// Whether neither side can still deliver mate: king against king, a single bishop
    /// or knight, or only bishops that all stand on squares of the same colour.
    public var hasInsufficientMaterial: Bool {
        if pawns | rooks | queens != 0 { return false }
        let minors = (knights | bishops).nonzeroBitCount
        if minors <= 1 { return true }
        if knights != 0 { return false }
        let lightSquares: UInt64 = 0x55AA_55AA_55AA_55AA
        return bishops & lightSquares == 0 || bishops & ~lightSquares == 0
    }
}
