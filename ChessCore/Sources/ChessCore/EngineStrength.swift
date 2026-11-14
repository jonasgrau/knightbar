/// One of eight playing strengths for the engine.
///
/// Levels 1–7 limit the engine to a fixed Elo rating, level 8 plays at full strength.
/// 1320 is the lowest rating Stockfish accepts.
public struct EngineStrength: Hashable, Sendable, Codable {
    public static let levels = 1...8
    private static let ratings = [1320, 1500, 1700, 1900, 2100, 2300, 2600]

    public let level: Int

    /// Levels outside 1–8 are clamped.
    public init(level: Int) {
        self.level = min(max(level, Self.levels.lowerBound), Self.levels.upperBound)
    }

    /// Clamps a stored level, too, so damaged settings cannot crash `elo`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(level: try container.decode(Int.self, forKey: .level))
    }

    /// The Elo limit, or `nil` for full strength.
    public var elo: Int? {
        level <= Self.ratings.count ? Self.ratings[level - 1] : nil
    }

    /// The UCI options that put the engine at this strength.
    var uciOptions: [(name: String, value: String)] {
        if let elo {
            [("UCI_LimitStrength", "true"), ("UCI_Elo", String(elo))]
        } else {
            [("UCI_LimitStrength", "false")]
        }
    }
}
