import Foundation

public enum PuzzleError: Error, Equatable, Sendable {
    /// The data is not the expected JSON.
    case malformed
    case invalidPosition
    /// The solution is empty or does not fit the position.
    case invalidSolution
}

/// A tactics puzzle: a position and the line of moves that solves it.
public struct Puzzle: Hashable, Sendable {
    public enum Source: String, Hashable, Sendable, Codable, CaseIterable {
        case lichess, chessCom
    }

    public var source: Source
    /// Identifies the puzzle within its source.
    public var id: String
    /// The position to solve. The side to move is the solver.
    public var position: Position
    /// The opponent's move that led to the position, if known.
    public var lastMove: Move?
    /// Solver and opponent moves in turn, starting with the solver.
    public var solution: [Move]
    public var title: String?
    /// The puzzle's page on the source's website.
    public var url: URL
    public var rating: Int?

    public init(
        source: Source, id: String, position: Position, lastMove: Move? = nil, solution: [Move],
        title: String? = nil, url: URL, rating: Int? = nil
    ) {
        self.source = source
        self.id = id
        self.position = position
        self.lastMove = lastMove
        self.solution = solution
        self.title = title
        self.url = url
        self.rating = rating
    }

    public var solverColor: PieceColor { position.sideToMove }
}

// MARK: - Decoding

extension Puzzle {
    /// Decodes the response of the given source's daily puzzle endpoint.
    public init(source: Source, data: Data) throws(PuzzleError) {
        switch source {
        case .lichess: try self.init(lichessJSON: data)
        case .chessCom: try self.init(chessComJSON: data)
        }
    }

    private struct LichessResponse: Decodable {
        struct Game: Decodable {
            let pgn: String
        }
        struct Details: Decodable {
            let id: String
            let rating: Int?
            let solution: [String]
            let fen: String?
            let lastMove: String?
        }
        let game: Game
        let puzzle: Details
    }

    /// Decodes the response of `GET https://lichess.org/api/puzzle/daily`.
    public init(lichessJSON data: Data) throws(PuzzleError) {
        guard let response = try? JSONDecoder().decode(LichessResponse.self, from: data),
              let url = URL(string: "https://lichess.org/training/\(response.puzzle.id)")
        else { throw .malformed }

        // The game's moves lead to the puzzle position. Replaying them is preferred over the
        // `fen` field, which is optional and carries neither castling rights nor move counters.
        let position: Position
        var lastMove = response.puzzle.lastMove.flatMap(Move.init(uci:))
        if let replayed = Self.replay(sanMoves: response.game.pgn) {
            position = replayed.position
            lastMove = replayed.lastMove ?? lastMove
        } else if let fen = response.puzzle.fen, let parsed = try? Position(fen: fen) {
            position = parsed
        } else {
            throw .invalidPosition
        }

        self.init(
            source: .lichess, id: response.puzzle.id, position: position, lastMove: lastMove,
            solution: try Self.validated(response.puzzle.solution, from: position),
            url: url, rating: response.puzzle.rating)
    }

    private struct ChessComResponse: Decodable {
        let title: String
        let url: URL
        let fen: String
        let pgn: String
    }

    /// Decodes the response of `GET https://api.chess.com/pub/puzzle`.
    public init(chessComJSON data: Data) throws(PuzzleError) {
        guard let response = try? JSONDecoder().decode(ChessComResponse.self, from: data) else {
            throw .malformed
        }
        guard let position = try? Position(fen: response.fen) else { throw .invalidPosition }

        // The solution only exists as PGN move text. Read it from the position in `fen`,
        // whether or not the PGN repeats that position in a tag.
        let moveText = response.pgn.split(separator: "\n").filter { !$0.hasPrefix("[") }.joined(separator: "\n")
        guard let game = try? PGNReader.read("[FEN \"\(response.fen)\"]\n\n\(moveText)"), !game.moves.isEmpty else {
            throw .invalidSolution
        }

        self.init(
            source: .chessCom, id: response.url.lastPathComponent, position: position,
            solution: game.moves, title: response.title, url: response.url)
    }

    /// Plays space-separated SAN moves from the starting position.
    private static func replay(sanMoves: String) -> (position: Position, lastMove: Move?)? {
        var position = Position.start
        var lastMove: Move?
        for san in sanMoves.split(whereSeparator: \.isWhitespace) {
            guard let move = position.move(san: String(san)) else { return nil }
            position = position.applying(move)
            lastMove = move
        }
        return (position, lastMove)
    }

    /// Checks that the UCI moves form a legal line from `start`.
    private static func validated(_ uciMoves: [String], from start: Position) throws(PuzzleError) -> [Move] {
        guard !uciMoves.isEmpty else { throw .invalidSolution }
        var position = start
        var moves: [Move] = []
        for text in uciMoves {
            guard let move = position.move(uci: text) else { throw .invalidSolution }
            moves.append(move)
            position = position.applying(move)
        }
        return moves
    }
}
