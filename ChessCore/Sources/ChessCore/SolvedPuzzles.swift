/// Remembers which puzzles have been solved.
public struct SolvedPuzzles: Hashable, Sendable, Codable {
    /// Oldest first.
    private var keys: [String] = []
    private var limit = 400

    /// Only the `limit` most recently solved puzzles are kept.
    public init(limit: Int = 400) {
        self.limit = limit
    }

    private static func key(_ source: Puzzle.Source, _ id: String) -> String {
        "\(source.rawValue):\(id)"
    }

    public func contains(source: Puzzle.Source, id: String) -> Bool {
        keys.contains(Self.key(source, id))
    }

    public func contains(_ puzzle: Puzzle) -> Bool {
        contains(source: puzzle.source, id: puzzle.id)
    }

    public mutating func insert(source: Puzzle.Source, id: String) {
        let key = Self.key(source, id)
        guard !keys.contains(key) else { return }
        keys.append(key)
        if keys.count > limit { keys.removeFirst(keys.count - limit) }
    }

    public mutating func insert(_ puzzle: Puzzle) {
        insert(source: puzzle.source, id: puzzle.id)
    }
}
