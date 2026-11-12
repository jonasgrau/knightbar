/// A square of the board. `index` runs from 0 (a1) through 7 (h1) to 63 (h8).
public struct Square: Hashable, Sendable {
    public let index: Int

    public init(index: Int) {
        precondition((0..<64).contains(index), "square index is off the board")
        self.index = index
    }

    /// `file` 0–7 maps to a–h, `rank` 0–7 maps to ranks 1–8.
    public init(file: Int, rank: Int) {
        precondition((0..<8).contains(file) && (0..<8).contains(rank), "square is off the board")
        self.index = rank * 8 + file
    }

    /// Reads a square name such as "e4".
    public init?(_ name: String) {
        let scalars = Array(name.unicodeScalars)
        guard scalars.count == 2 else { return nil }
        let file = Int(scalars[0].value) - 97
        let rank = Int(scalars[1].value) - 49
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        self.init(file: file, rank: rank)
    }

    public var file: Int { index & 7 }
    public var rank: Int { index >> 3 }

    public var name: String {
        "\(Character(UnicodeScalar(UInt8(97 + file))))\(rank + 1)"
    }

    /// Light squares include h1 and a8.
    public var isLight: Bool { (file + rank) % 2 == 1 }

    public static let all: [Square] = (0..<64).map(Square.init(index:))

    var bit: UInt64 { 1 << UInt64(index) }

    func offset(file df: Int, rank dr: Int) -> Square? {
        let f = file + df, r = rank + dr
        guard (0..<8).contains(f), (0..<8).contains(r) else { return nil }
        return Square(file: f, rank: r)
    }
}

extension Square: CustomStringConvertible {
    public var description: String { name }
}
