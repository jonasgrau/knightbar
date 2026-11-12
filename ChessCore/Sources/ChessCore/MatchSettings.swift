/// The player's choices for games in the popover.
public struct MatchSettings: Hashable, Sendable, Codable {
    public enum Opponent: String, Hashable, Sendable, Codable, CaseIterable {
        case computer, human
    }

    public enum ColorChoice: String, Hashable, Sendable, Codable, CaseIterable {
        case white, black, random

        /// The colour to play. `random` picks one with `generator`.
        public func resolved<G: RandomNumberGenerator>(using generator: inout G) -> PieceColor {
            switch self {
            case .white: .white
            case .black: .black
            case .random: Bool.random(using: &generator) ? .white : .black
            }
        }

        public func resolved() -> PieceColor {
            var generator = SystemRandomNumberGenerator()
            return resolved(using: &generator)
        }
    }

    /// Thinking times offered for the engine, in seconds per move.
    public static let moveTimes: [Double] = [0.5, 1, 2, 5]

    public var opponent: Opponent = .computer
    /// The colour the human plays against the computer.
    public var colorChoice: ColorChoice = .white
    public var strength = EngineStrength(level: 3)
    /// The engine's thinking time per move in seconds.
    public var moveTime: Double = 1

    public init() {}

    /// The colours moved through the board when the human plays `color`.
    public func humanColors(playingAs color: PieceColor) -> Set<PieceColor> {
        opponent == .human ? [.white, .black] : [color]
    }
}
