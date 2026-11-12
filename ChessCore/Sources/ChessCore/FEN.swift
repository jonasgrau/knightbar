public enum FENError: Error, Equatable, Sendable {
    case wrongFieldCount
    case invalidBoard
    case invalidSideToMove
    case invalidCastling
    case invalidEnPassant
    case invalidClock
    /// Each side needs exactly one king.
    case invalidKings
}

extension Position {
    /// Reads a position in Forsyth–Edwards Notation.
    ///
    /// The two counters at the end may be omitted and then default to "0 1".
    public init(fen: String) throws(FENError) {
        let fields = fen.split(separator: " ")
        guard fields.count == 4 || fields.count == 6 else { throw .wrongFieldCount }
        self.init()

        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { throw .invalidBoard }
        for (row, text) in ranks.enumerated() {
            let rank = 7 - row
            var file = 0
            for character in text {
                if let gap = character.wholeNumberValue {
                    guard (1...8).contains(gap) else { throw .invalidBoard }
                    file += gap
                } else {
                    guard file < 8, let piece = Piece(fenCharacter: character) else { throw .invalidBoard }
                    guard piece.kind != .pawn || (rank != 0 && rank != 7) else { throw .invalidBoard }
                    put(piece, at: Square(file: file, rank: rank))
                    file += 1
                }
            }
            guard file == 8 else { throw .invalidBoard }
        }
        guard (kings & white).nonzeroBitCount == 1, (kings & black).nonzeroBitCount == 1 else {
            throw .invalidKings
        }

        switch fields[1] {
        case "w": sideToMove = .white
        case "b": sideToMove = .black
        default: throw .invalidSideToMove
        }

        if fields[2] != "-" {
            for character in fields[2] {
                let right: CastlingRights
                switch character {
                case "K": right = .whiteKingside
                case "Q": right = .whiteQueenside
                case "k": right = .blackKingside
                case "q": right = .blackQueenside
                default: throw .invalidCastling
                }
                guard !castlingRights.contains(right) else { throw .invalidCastling }
                castlingRights.insert(right)
            }
        }

        if fields[3] != "-" {
            // After a white double step (black to move) the square is on rank 3, otherwise on rank 6.
            guard let square = Square(String(fields[3])),
                  square.rank == (sideToMove == .white ? 5 : 2)
            else { throw .invalidEnPassant }
            enPassantSquare = square
        }

        if fields.count == 6 {
            guard let halfmoves = Int(fields[4]), halfmoves >= 0,
                  let fullmoves = Int(fields[5]), fullmoves >= 1
            else { throw .invalidClock }
            halfmoveClock = halfmoves
            fullmoveNumber = fullmoves
        }
    }

    public var fen: String {
        var board = ""
        for rank in (0..<8).reversed() {
            var gap = 0
            for file in 0..<8 {
                if let piece = self[Square(file: file, rank: rank)] {
                    if gap > 0 { board += String(gap); gap = 0 }
                    board.append(piece.fenCharacter)
                } else {
                    gap += 1
                }
            }
            if gap > 0 { board += String(gap) }
            if rank > 0 { board += "/" }
        }

        var castling = ""
        if castlingRights.contains(.whiteKingside) { castling += "K" }
        if castlingRights.contains(.whiteQueenside) { castling += "Q" }
        if castlingRights.contains(.blackKingside) { castling += "k" }
        if castlingRights.contains(.blackQueenside) { castling += "q" }
        if castling.isEmpty { castling = "-" }

        return [
            board,
            sideToMove == .white ? "w" : "b",
            castling,
            enPassantSquare?.name ?? "-",
            String(halfmoveClock),
            String(fullmoveNumber),
        ].joined(separator: " ")
    }
}
