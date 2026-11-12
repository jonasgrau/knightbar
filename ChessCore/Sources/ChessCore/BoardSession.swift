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
    public private(set) var selectedSquare: Square?
    public private(set) var pendingPromotion: PendingPromotion?
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
        guard let selectedSquare else { return [] }
        var seen = Set<Square>()
        return game.legalMoves.filter { $0.from == selectedSquare && seen.insert($0.to).inserted }.map(\.to)
    }

    /// Square of the king that is currently in check.
    public var checkedKingSquare: Square? {
        let position = game.position
        return position.isInCheck ? position.kingSquare(of: position.sideToMove) : nil
    }

    /// Whether `square` holds a piece that may move now.
    public func canSelect(_ square: Square) -> Bool {
        guard pendingPromotion == nil, isHumanTurn else { return false }
        return game.position[square]?.color == game.position.sideToMove
    }

    /// Selects the piece on `square`. Returns `false` if there is no movable piece there.
    @discardableResult
    public mutating func select(_ square: Square) -> Bool {
        guard canSelect(square) else { return false }
        selectedSquare = square
        return true
    }

    public mutating func deselect() {
        selectedSquare = nil
    }

    /// A click on `square`: moves the selected piece there, selects one of the mover's pieces,
    /// or clears the selection.
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

    /// Moves from `from` to `to`, for example after a dragged piece is dropped.
    ///
    /// Returns `true` if the move was played. If the move needs a promotion piece,
    /// it is kept in `pendingPromotion` and only played by `promote(to:)`.
    @discardableResult
    public mutating func move(from: Square, to: Square) -> Bool {
        guard pendingPromotion == nil, isHumanTurn else { return false }
        selectedSquare = nil
        let candidates = game.legalMoves.filter { $0.from == from && $0.to == to }
        guard let first = candidates.first else { return false }
        if first.promotion != nil {
            pendingPromotion = PendingPromotion(from: from, to: to, color: game.position.sideToMove)
            return false
        }
        return game.make(first)
    }

    public mutating func promote(to kind: PieceKind) {
        guard let pending = pendingPromotion else { return }
        pendingPromotion = nil
        game.make(Move(from: pending.from, to: pending.to, promotion: kind))
    }

    public mutating func cancelPromotion() {
        pendingPromotion = nil
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
        selectedSquare = nil
        pendingPromotion = nil
    }
}
