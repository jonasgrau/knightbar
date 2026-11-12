import Foundation

public enum SavedGameError: Error, Equatable, Sendable {
    case invalidPosition
    case invalidMove(String)
}

/// A game in a form that can be written to disk: starting position and moves as text.
public struct SavedGame: Hashable, Sendable, Codable {
    public var startFEN: String
    /// The moves in UCI notation.
    public var moves: [String]
    public var resignedBy: PieceColor?
    /// The colour the human plays against the computer.
    public var playerColor: PieceColor

    public init(game: Game, playerColor: PieceColor) {
        startFEN = game.startPosition.fen
        moves = game.moves.map(\.uci)
        resignedBy = game.resignedBy
        self.playerColor = playerColor
    }

    /// Rebuilds the game by replaying the moves. Throws if the data does not describe a legal game.
    public func restoredGame() throws(SavedGameError) -> Game {
        guard let position = try? Position(fen: startFEN) else { throw .invalidPosition }
        var game = Game(position: position)
        for text in moves {
            guard let move = Move(uci: text), game.make(move) else { throw .invalidMove(text) }
        }
        if let resignedBy { game.resign(resignedBy) }
        return game
    }
}

/// Reads and writes the saved game as a JSON file.
public struct SavedGameStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The saved game, or `nil` if nothing has been saved yet. Throws if the file is unreadable.
    public func load() throws -> SavedGame? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(SavedGame.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ game: SavedGame) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(game).write(to: fileURL, options: .atomic)
    }
}
