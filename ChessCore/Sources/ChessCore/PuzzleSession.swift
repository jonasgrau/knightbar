/// Solving a puzzle on the board: checks the solver's moves against the solution.
public struct PuzzleSession: Sendable {
    public enum State: Hashable, Sendable {
        /// The solver has to find the next move.
        case solving
        /// A correct move was played and the opponent's answer is due.
        case awaitingReply
        case solved
    }

    public enum Hint: Hashable, Sendable {
        /// The piece that has to move.
        case piece(Square)
        case move(Move)
    }

    public let puzzle: Puzzle
    public private(set) var state = State.solving
    public private(set) var selectedSquare: Square?
    public private(set) var pendingPromotion: PendingPromotion?
    /// Number of wrong moves tried so far.
    public private(set) var mistakes = 0
    /// Whether the most recent attempt was a wrong move.
    public private(set) var lastAttemptFailed = false
    public private(set) var hint: Hint?
    public private(set) var hintsUsed = false

    private var game: Game
    /// Index of the next move in `puzzle.solution`.
    private var progress = 0

    public init(puzzle: Puzzle) {
        self.puzzle = puzzle
        game = Game(position: puzzle.position)
    }

    public var position: Position { game.position }

    /// The move to highlight: the last one played, or the opponent's move that led to the puzzle.
    public var lastMove: Move? { game.lastMove ?? puzzle.lastMove }

    public var targetSquares: [Square] {
        guard let selectedSquare else { return [] }
        var seen = Set<Square>()
        return position.legalMoves(from: selectedSquare).filter { seen.insert($0.to).inserted }.map(\.to)
    }

    public var checkedKingSquare: Square? {
        position.isInCheck ? position.kingSquare(of: position.sideToMove) : nil
    }

    public func canSelect(_ square: Square) -> Bool {
        guard state == .solving, pendingPromotion == nil else { return false }
        return position[square]?.color == puzzle.solverColor
    }

    @discardableResult
    public mutating func select(_ square: Square) -> Bool {
        guard canSelect(square) else { return false }
        selectedSquare = square
        lastAttemptFailed = false
        return true
    }

    public mutating func deselect() {
        selectedSquare = nil
    }

    public mutating func tap(_ square: Square) {
        guard pendingPromotion == nil else { return }
        if let selectedSquare {
            if square == selectedSquare {
                deselect()
            } else if targetSquares.contains(square) {
                move(from: selectedSquare, to: square)
            } else if !select(square) {
                deselect()
            }
        } else {
            select(square)
        }
    }

    /// Tries the move as the solver's next move. Returns `true` if it was correct and has been played.
    @discardableResult
    public mutating func move(from: Square, to: Square) -> Bool {
        guard state == .solving, pendingPromotion == nil else { return false }
        selectedSquare = nil
        let candidates = position.legalMoves().filter { $0.from == from && $0.to == to }
        guard let first = candidates.first else { return false }
        if first.promotion != nil {
            pendingPromotion = PendingPromotion(from: from, to: to, color: puzzle.solverColor)
            return false
        }
        return attempt(first)
    }

    public mutating func promote(to kind: PieceKind) {
        guard let pending = pendingPromotion else { return }
        pendingPromotion = nil
        attempt(Move(from: pending.from, to: pending.to, promotion: kind))
    }

    public mutating func cancelPromotion() {
        pendingPromotion = nil
    }

    @discardableResult
    private mutating func attempt(_ move: Move) -> Bool {
        // promote(to:) accepts any piece kind, so the move may not be legal at all.
        guard position.isLegal(move) else { return false }
        let expected = puzzle.solution[progress]
        let mates = position.applying(move).isCheckmate
        guard move == expected || mates else {
            mistakes += 1
            lastAttemptFailed = true
            return false
        }
        game.make(move)
        progress += 1
        lastAttemptFailed = false
        hint = nil
        // Any mate ends the puzzle, even if the listed solution is longer.
        state = (mates || progress == puzzle.solution.count) ? .solved : .awaitingReply
        return true
    }

    /// Plays the opponent's answer from the solution.
    public mutating func playReply() {
        guard state == .awaitingReply else { return }
        game.make(puzzle.solution[progress])
        progress += 1
        state = progress == puzzle.solution.count ? .solved : .solving
    }

    /// Shows the piece to move first; asked again, the whole move.
    public mutating func showHint() {
        guard state == .solving else { return }
        let next = puzzle.solution[progress]
        hintsUsed = true
        hint = hint == nil ? .piece(next.from) : .move(next)
    }

    /// Starts the puzzle over.
    public mutating func restart() {
        self = PuzzleSession(puzzle: puzzle)
    }
}

extension Position {
    /// Whether the side to move is checkmated.
    public var isCheckmate: Bool { isInCheck && legalMoves().isEmpty }
}
