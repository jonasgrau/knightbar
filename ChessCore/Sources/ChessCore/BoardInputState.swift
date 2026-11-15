/// The result of applying a tap to a board's shared input state.
enum BoardInputAction: Equatable {
    case ignored
    case selected
    case deselected
    case move(from: Square, to: Square)
}

/// How a legal input move should be completed by its owning session.
enum BoardMoveResult: Equatable {
    case rejected
    /// The move needs a promotion piece; it is kept as the pending promotion.
    case promotion
    case move(Move)
}

/// The input shared by game and puzzle boards. Sessions decide whether a selection is allowed
/// and what to do with a completed move.
struct BoardInputState: Sendable {
    private(set) var selectedSquare: Square?
    private(set) var pendingPromotion: PendingPromotion?

    func targetSquares(in legalMoves: @autoclosure () -> [Move]) -> [Square] {
        guard let selectedSquare else { return [] }
        var seen = Set<Square>()
        return legalMoves().filter { $0.from == selectedSquare && seen.insert($0.to).inserted }.map(\.to)
    }

    func canSelect(_ square: Square, in position: Position, color: PieceColor, isEnabled: Bool) -> Bool {
        guard pendingPromotion == nil, isEnabled else { return false }
        return position[square]?.color == color
    }

    @discardableResult
    mutating func select(_ square: Square, in position: Position, color: PieceColor, isEnabled: Bool) -> Bool {
        guard canSelect(square, in: position, color: color, isEnabled: isEnabled) else { return false }
        selectedSquare = square
        return true
    }

    mutating func deselect() {
        selectedSquare = nil
    }

    mutating func tap(
        _ square: Square, in position: Position, legalMoves: @autoclosure () -> [Move], color: PieceColor, isEnabled: Bool
    ) -> BoardInputAction {
        guard pendingPromotion == nil else { return .ignored }
        if let selectedSquare {
            if square == selectedSquare {
                deselect()
                return .deselected
            }
            if targetSquares(in: legalMoves()).contains(square) {
                return .move(from: selectedSquare, to: square)
            }
            if select(square, in: position, color: color, isEnabled: isEnabled) { return .selected }
            deselect()
            return .deselected
        }
        return select(square, in: position, color: color, isEnabled: isEnabled) ? .selected : .ignored
    }

    mutating func prepareMove(
        from: Square, to: Square, legalMoves: @autoclosure () -> [Move], promotionColor: PieceColor, isEnabled: Bool
    ) -> BoardMoveResult {
        guard pendingPromotion == nil, isEnabled else { return .rejected }
        selectedSquare = nil
        guard let move = legalMoves().first(where: { $0.from == from && $0.to == to }) else { return .rejected }
        if move.promotion != nil {
            pendingPromotion = PendingPromotion(from: from, to: to, color: promotionColor)
            return .promotion
        }
        return .move(move)
    }

    mutating func promote(to kind: PieceKind) -> Move? {
        guard let pending = pendingPromotion else { return nil }
        pendingPromotion = nil
        return Move(from: pending.from, to: pending.to, promotion: kind)
    }

    mutating func cancelPromotion() {
        pendingPromotion = nil
    }

    mutating func clear() {
        selectedSquare = nil
        pendingPromotion = nil
    }
}
