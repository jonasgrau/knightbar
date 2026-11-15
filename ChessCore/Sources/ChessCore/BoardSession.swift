/// A pawn move to the last rank that still needs a promotion piece.
public struct PendingPromotion: Hashable, Sendable {
    public let from: Square
    public let to: Square
    public let color: PieceColor

    public init(from: Square, to: Square, color: PieceColor) {
        self.from = from
        self.to = to
        self.color = color
    }
}

/// A game together with the board's input state: the selected square and a pending promotion.
///
/// The UI reports clicks and dropped pieces; this type decides what follows from them.
/// Colours not listed in `humanColors` are played by the engine through `playEngineMove(_:)`.
public struct BoardSession: Sendable {
    public private(set) var game: Game
    private var input = BoardInputState()
    public var selectedSquare: Square? { input.selectedSquare }
    public var pendingPromotion: PendingPromotion? { input.pendingPromotion }
    /// The colours moved through the board. Both colours means a two-player game.
    public var humanColors: Set<PieceColor> {
        didSet { clearInput() }
    }

    public init(game: Game = Game(), humanColors: Set<PieceColor> = [.white, .black]) {
        self.game = game
        self.humanColors = humanColors
    }

    private var isHumanTurn: Bool {
        !game.status.isOver && humanColors.contains(game.position.sideToMove)
    }

    /// Whether the engine has to move now.
    public var isEngineTurn: Bool {
        !game.status.isOver && !humanColors.contains(game.position.sideToMove)
    }

    /// Squares the selected piece can move to.
    public var targetSquares: [Square] {
        input.targetSquares(in: game.legalMoves)
    }

    /// Square of the king that is currently in check.
    public var checkedKingSquare: Square? {
        game.position.checkedKingSquare
    }

    /// Whether `square` holds a piece that may move now.
    public func canSelect(_ square: Square) -> Bool {
        input.canSelect(square, in: game.position, color: game.position.sideToMove, isEnabled: isHumanTurn)
    }

    /// Selects the piece on `square`. Returns `false` if there is no movable piece there.
    @discardableResult
    public mutating func select(_ square: Square) -> Bool {
        input.select(square, in: game.position, color: game.position.sideToMove, isEnabled: isHumanTurn)
    }

    public mutating func deselect() {
        input.deselect()
    }

    /// A click on `square`: moves the selected piece there, selects one of the mover's pieces,
    /// or clears the selection.
    public mutating func tap(_ square: Square) {
        let action = input.tap(
            square, in: game.position, legalMoves: game.legalMoves,
            color: game.position.sideToMove, isEnabled: isHumanTurn)
        if case .move(let from, let to) = action {
            move(from: from, to: to)
        }
    }

    /// Moves from `from` to `to`, for example after a dragged piece is dropped.
    ///
    /// Returns `true` if the move was played. If the move needs a promotion piece,
    /// it is kept in `pendingPromotion` and only played by `promote(to:)`.
    @discardableResult
    public mutating func move(from: Square, to: Square) -> Bool {
        switch input.prepareMove(
            from: from, to: to, legalMoves: game.legalMoves,
            promotionColor: game.position.sideToMove, isEnabled: isHumanTurn) {
        case .move(let move):
            return game.make(move)
        case .promotion, .rejected:
            return false
        }
    }

    public mutating func promote(to kind: PieceKind) {
        guard let move = input.promote(to: kind) else { return }
        game.make(move)
    }

    public mutating func cancelPromotion() {
        input.cancelPromotion()
    }

    /// Plays the engine's reply. Returns `false` if it is not the engine's turn or the move is illegal.
    @discardableResult
    public mutating func playEngineMove(_ move: Move) -> Bool {
        guard isEngineTurn else { return false }
        return game.make(move)
    }

    /// Whether there is something the human can take back: a resignation or one of their own moves.
    public var canUndo: Bool {
        if game.resignedBy != nil { return true }
        return zip(game.positions, game.moves).contains { position, _ in
            humanColors.contains(position.sideToMove)
        }
    }

    /// Takes back the human's last move, together with the engine's reply if it has already been played.
    public mutating func undo() {
        guard canUndo else { return }
        clearInput()
        if game.resignedBy != nil {
            game.undo()
            return
        }
        repeat {
            game.undo()
        } while !humanColors.contains(game.position.sideToMove) && !game.moves.isEmpty
    }

    /// The human gives up. In a two-player game the side to move resigns.
    public mutating func resign() {
        let color = humanColors.count == 1 ? humanColors.first! : game.position.sideToMove
        clearInput()
        game.resign(color)
    }

    /// Starts a new game, optionally changing who is played through the board.
    public mutating func newGame(humanColors: Set<PieceColor>? = nil) {
        if let humanColors { self.humanColors = humanColors }
        clearInput()
        game = Game()
    }

    private mutating func clearInput() {
        input.clear()
    }
}
