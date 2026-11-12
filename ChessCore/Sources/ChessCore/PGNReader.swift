public enum PGNError: Error, Equatable, Sendable {
    case invalidFEN
    case illegalMove(String)
}

/// The content of a PGN game: its tags and the moves of the main line.
public struct PGNGame: Sendable {
    public var tags: [String: String]
    public var startPosition: Position
    public var moves: [Move]
}

public enum PGNReader {
    private static let results: Set<String> = ["1-0", "0-1", "1/2-1/2", "*"]

    /// Reads one game. Comments, variations and annotation glyphs are skipped.
    /// A "FEN" tag sets the starting position.
    public static func read(_ text: String) throws(PGNError) -> PGNGame {
        var tags: [String: String] = [:]
        var words: [String] = []
        var word = ""

        func endWord() {
            if !word.isEmpty { words.append(word) }
            word = ""
        }

        var index = text.startIndex
        func next() -> Character? {
            guard index < text.endIndex else { return nil }
            defer { index = text.index(after: index) }
            return text[index]
        }

        while let character = next() {
            switch character {
            case "[" where words.isEmpty && word.isEmpty:
                var name = ""
                var value = ""
                var inValue = false
                var closed = false
                while !closed, let tagCharacter = next() {
                    switch tagCharacter {
                    case "]" where !inValue: closed = true
                    case "\"": inValue.toggle()
                    case "\\" where inValue: if let escaped = next() { value.append(escaped) }
                    default:
                        if inValue { value.append(tagCharacter) } else if !tagCharacter.isWhitespace { name.append(tagCharacter) }
                    }
                }
                if !name.isEmpty { tags[name] = value }
            case "{":
                endWord()
                while let skipped = next(), skipped != "}" {}
            case ";":
                endWord()
                while let skipped = next(), !skipped.isNewline {}
            case "(":
                endWord()
                var depth = 1
                while depth > 0, let skipped = next() {
                    switch skipped {
                    case "(": depth += 1
                    case ")": depth -= 1
                    case "{": while let inner = next(), inner != "}" {}
                    default: break
                    }
                }
            case _ where character.isWhitespace:
                endWord()
            default:
                word.append(character)
            }
        }
        endWord()

        var position = Position.start
        if let fen = tags["FEN"] {
            guard let parsed = try? Position(fen: fen) else { throw .invalidFEN }
            position = parsed
        }
        let start = position

        var moves: [Move] = []
        for word in words where !results.contains(word) && !word.hasPrefix("$") {
            // Drop a move number such as "12." or "12..." in front of the move.
            var san = Substring(word)
            let digits = san.prefix { $0.isNumber }
            if san.dropFirst(digits.count).first == "." {
                san = san.dropFirst(digits.count).drop { $0 == "." }
            } else {
                san = san.drop { $0 == "." }
            }
            guard !san.isEmpty else { continue }
            guard let move = position.move(san: String(san)) else { throw .illegalMove(String(san)) }
            moves.append(move)
            position = position.applying(move)
        }
        return PGNGame(tags: tags, startPosition: start, moves: moves)
    }
}
