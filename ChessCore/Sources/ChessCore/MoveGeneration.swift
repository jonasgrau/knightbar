private enum Tables {
    static let knightSteps = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
    static let kingSteps = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
    static let diagonals = [(1, 1), (-1, 1), (-1, -1), (1, -1)]
    static let straights = [(1, 0), (0, 1), (-1, 0), (0, -1)]

    static let knight = masks(for: knightSteps)
    static let king = masks(for: kingSteps)
    /// Per square: the squares from which a pawn of that colour attacks it.
    static let whitePawnAttackers = masks(for: [(1, -1), (-1, -1)])
    static let blackPawnAttackers = masks(for: [(1, 1), (-1, 1)])

    private static func masks(for steps: [(Int, Int)]) -> [UInt64] {
        Square.all.map { square in
            steps.reduce(UInt64(0)) { mask, step in
                mask | (square.offset(file: step.0, rank: step.1)?.bit ?? 0)
            }
        }
    }

    /// Castling rights that are lost once a piece moves from this square or captures on it.
    static let castlingLoss: [CastlingRights] = Square.all.map { square in
        switch square.name {
        case "a1": .whiteQueenside
        case "h1": .whiteKingside
        case "e1": [.whiteKingside, .whiteQueenside]
        case "a8": .blackQueenside
        case "h8": .blackKingside
        case "e8": [.blackKingside, .blackQueenside]
        default: []
        }
    }
}

extension Position {
    // MARK: - Attacks

    /// Whether `square` is attacked by a piece of `color`.
    public func isAttacked(_ square: Square, by color: PieceColor) -> Bool {
        let attackers = mask(of: color)
        let index = square.index
        if Tables.knight[index] & knights & attackers != 0 { return true }
        if Tables.king[index] & kings & attackers != 0 { return true }
        let pawnSources = color == .white ? Tables.whitePawnAttackers[index] : Tables.blackPawnAttackers[index]
        if pawnSources & pawns & attackers != 0 { return true }
        return sliderAttacks(square, along: Tables.diagonals, sliders: (bishops | queens) & attackers)
            || sliderAttacks(square, along: Tables.straights, sliders: (rooks | queens) & attackers)
    }

    private func sliderAttacks(_ square: Square, along directions: [(Int, Int)], sliders: UInt64) -> Bool {
        guard sliders != 0 else { return false }
        let blockers = occupied
        for (df, dr) in directions {
            var current = square
            while let next = current.offset(file: df, rank: dr) {
                if blockers & next.bit != 0 {
                    if sliders & next.bit != 0 { return true }
                    break
                }
                current = next
            }
        }
        return false
    }

    /// Whether the king of the side to move is in check.
    public var isInCheck: Bool { isKingAttacked(sideToMove) }

    func isKingAttacked(_ color: PieceColor) -> Bool {
        guard let king = kingSquare(of: color) else { return false }
        return isAttacked(king, by: color.opposite)
    }

    // MARK: - Moves

    /// All legal moves of the side to move.
    public func legalMoves() -> [Move] {
        let mover = sideToMove
        return pseudoLegalMoves().filter { !applying($0).isKingAttacked(mover) }
    }

    /// Legal moves of the piece on `square`.
    public func legalMoves(from square: Square) -> [Move] {
        legalMoves().filter { $0.from == square }
    }

    public func isLegal(_ move: Move) -> Bool {
        legalMoves().contains(move)
    }

    /// Moves by the pieces' movement rules, without checking whether the mover's king ends up in check.
    func pseudoLegalMoves() -> [Move] {
        var moves: [Move] = []
        moves.reserveCapacity(48)
        let own = mask(of: sideToMove)
        let enemy = mask(of: sideToMove.opposite)

        var remaining = own
        while remaining != 0 {
            let from = Square(index: remaining.trailingZeroBitCount)
            remaining &= remaining - 1
            let bit = from.bit

            if pawns & bit != 0 {
                addPawnMoves(from: from, enemy: enemy, to: &moves)
            } else if knights & bit != 0 {
                addStepMoves(from: from, targets: Tables.knight[from.index] & ~own, to: &moves)
            } else if kings & bit != 0 {
                addStepMoves(from: from, targets: Tables.king[from.index] & ~own, to: &moves)
                addCastlingMoves(from: from, to: &moves)
            } else {
                if (bishops | queens) & bit != 0 {
                    addSlidingMoves(from: from, along: Tables.diagonals, own: own, enemy: enemy, to: &moves)
                }
                if (rooks | queens) & bit != 0 {
                    addSlidingMoves(from: from, along: Tables.straights, own: own, enemy: enemy, to: &moves)
                }
            }
        }
        return moves
    }

    private func addStepMoves(from: Square, targets: UInt64, to moves: inout [Move]) {
        var remaining = targets
        while remaining != 0 {
            moves.append(Move(from: from, to: Square(index: remaining.trailingZeroBitCount)))
            remaining &= remaining - 1
        }
    }

    private func addSlidingMoves(
        from: Square, along directions: [(Int, Int)], own: UInt64, enemy: UInt64, to moves: inout [Move]
    ) {
        for (df, dr) in directions {
            var current = from
            while let next = current.offset(file: df, rank: dr) {
                if own & next.bit != 0 { break }
                moves.append(Move(from: from, to: next))
                if enemy & next.bit != 0 { break }
                current = next
            }
        }
    }

    private func addPawnMoves(from: Square, enemy: UInt64, to moves: inout [Move]) {
        let forward = sideToMove == .white ? 1 : -1
        let startRank = sideToMove == .white ? 1 : 6
        let lastRank = sideToMove == .white ? 7 : 0

        func add(_ target: Square) {
            if target.rank == lastRank {
                for kind in Move.promotionKinds { moves.append(Move(from: from, to: target, promotion: kind)) }
            } else {
                moves.append(Move(from: from, to: target))
            }
        }

        if let one = from.offset(file: 0, rank: forward), occupied & one.bit == 0 {
            add(one)
            if from.rank == startRank, let two = one.offset(file: 0, rank: forward), occupied & two.bit == 0 {
                add(two)
            }
        }
        for side in [-1, 1] {
            guard let target = from.offset(file: side, rank: forward) else { continue }
            if enemy & target.bit != 0 || target == enPassantSquare {
                add(target)
            }
        }
    }

    private func addCastlingMoves(from king: Square, to moves: inout [Move]) {
        let rank = sideToMove == .white ? 0 : 7
        guard king == Square(file: 4, rank: rank) else { return }
        let enemy = sideToMove.opposite
        let ownRooks = rooks & mask(of: sideToMove)

        func isFree(_ files: ClosedRange<Int>) -> Bool {
            files.allSatisfy { occupied & Square(file: $0, rank: rank).bit == 0 }
        }
        func isSafe(_ files: ClosedRange<Int>) -> Bool {
            files.allSatisfy { !isAttacked(Square(file: $0, rank: rank), by: enemy) }
        }

        let kingside: CastlingRights = sideToMove == .white ? .whiteKingside : .blackKingside
        if castlingRights.contains(kingside), ownRooks & Square(file: 7, rank: rank).bit != 0,
           isFree(5...6), isSafe(4...6) {
            moves.append(Move(from: king, to: Square(file: 6, rank: rank)))
        }
        let queenside: CastlingRights = sideToMove == .white ? .whiteQueenside : .blackQueenside
        if castlingRights.contains(queenside), ownRooks & Square(file: 0, rank: rank).bit != 0,
           isFree(1...3), isSafe(2...4) {
            moves.append(Move(from: king, to: Square(file: 2, rank: rank)))
        }
    }

    // MARK: - Making a move

    /// Whether `move` captures, including en passant.
    public func isCapture(_ move: Move) -> Bool {
        if occupied & move.to.bit != 0 { return true }
        return isEnPassant(move)
    }

    func isEnPassant(_ move: Move) -> Bool {
        move.to == enPassantSquare && pawns & move.from.bit != 0 && move.from.file != move.to.file
    }

    func isCastling(_ move: Move) -> Bool {
        kings & move.from.bit != 0 && abs(move.to.file - move.from.file) == 2
    }

    /// The position after `move`.
    ///
    /// The move must come from `legalMoves()`. If there is no piece on the origin square,
    /// the position is returned unchanged.
    public func applying(_ move: Move) -> Position {
        guard let piece = self[move.from] else { return self }
        var next = self
        let capture = isCapture(move)

        if isEnPassant(move) {
            next.remove(at: Square(file: move.to.file, rank: move.from.rank))
        }
        next.remove(at: move.from)
        next.put(Piece(color: piece.color, kind: move.promotion ?? piece.kind), at: move.to)

        if isCastling(move) {
            let rank = move.from.rank
            let kingside = move.to.file == 6
            next.remove(at: Square(file: kingside ? 7 : 0, rank: rank))
            next.put(Piece(color: piece.color, kind: .rook), at: Square(file: kingside ? 5 : 3, rank: rank))
        }

        next.castlingRights.subtract(Tables.castlingLoss[move.from.index])
        next.castlingRights.subtract(Tables.castlingLoss[move.to.index])

        if piece.kind == .pawn, abs(move.to.rank - move.from.rank) == 2 {
            next.enPassantSquare = Square(file: move.from.file, rank: (move.from.rank + move.to.rank) / 2)
        } else {
            next.enPassantSquare = nil
        }

        next.halfmoveClock = (piece.kind == .pawn || capture) ? 0 : halfmoveClock + 1
        if sideToMove == .black { next.fullmoveNumber += 1 }
        next.sideToMove = sideToMove.opposite
        return next
    }

    // MARK: - Perft

    /// Counts all move sequences of length `depth`. Used to verify move generation.
    public func perft(depth: Int) -> Int {
        guard depth > 0 else { return 1 }
        let moves = legalMoves()
        if depth == 1 { return moves.count }
        return moves.reduce(0) { $0 + applying($1).perft(depth: depth - 1) }
    }
}
