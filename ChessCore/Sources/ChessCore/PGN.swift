extension Game {
    /// Result in PGN notation: "1-0", "0-1", "1/2-1/2", or "*" for games in progress.
    public var pgnResult: String {
        switch status {
        case .ongoing: "*"
        case .checkmate(let winner), .resigned(let winner): winner == .white ? "1-0" : "0-1"
        case .stalemate, .draw: "1/2-1/2"
        }
    }

    /// The moves in standard algebraic notation, without move numbers or result.
    public var sanMoves: [String] {
        zip(positions, moves).map { $0.san(for: $1) }
    }

    /// Exports the game as PGN.
    ///
    /// `tags` overrides the Seven Tag Roster entries (Event, Site, Date, Round, White, Black)
    /// or adds further ones. The result and, for a non-standard starting position,
    /// "SetUp" and "FEN" are always derived from the game.
    public func pgn(tags: [String: String] = [:]) -> String {
        let roster = ["Event", "Site", "Date", "Round", "White", "Black"]
        var pairs = roster.map { ($0, tags[$0] ?? ($0 == "Date" ? "????.??.??" : "?")) }
        pairs.append(("Result", pgnResult))
        if startPosition != .start {
            pairs.append(("SetUp", "1"))
            pairs.append(("FEN", startPosition.fen))
        }
        let derived = Set(roster + ["Result", "SetUp", "FEN"])
        for name in tags.keys.sorted() where !derived.contains(name) {
            pairs.append((name, tags[name]!))
        }

        let header = pairs.map { name, value in
            let escaped = value
                .replacing("\\", with: "\\\\")
                .replacing("\"", with: "\\\"")
            return "[\(name) \"\(escaped)\"]"
        }.joined(separator: "\n")

        var tokens: [String] = []
        for (index, (position, san)) in zip(positions, sanMoves).enumerated() {
            if position.sideToMove == .white {
                tokens.append("\(position.fullmoveNumber).")
            } else if index == 0 {
                tokens.append("\(position.fullmoveNumber)...")
            }
            tokens.append(san)
        }
        tokens.append(pgnResult)

        var lines: [String] = []
        var line = ""
        for token in tokens {
            if !line.isEmpty, line.count + 1 + token.count > 80 {
                lines.append(line)
                line = token
            } else {
                line += line.isEmpty ? token : " " + token
            }
        }
        lines.append(line)

        return header + "\n\n" + lines.joined(separator: "\n") + "\n"
    }
}
