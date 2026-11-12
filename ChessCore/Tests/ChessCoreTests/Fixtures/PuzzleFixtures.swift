/// Real responses of the two daily puzzle endpoints, fetched on 2026-11-12.
/// Personal names in both responses are replaced by placeholders.
enum PuzzleFixtures {
    static let lichess = #"""
{
  "game": {
    "id": "CzsqNwrA",
    "perf": {
      "key": "rapid",
      "name": "Rapid"
    },
    "rated": true,
    "players": [
      {
        "color": "white",
        "rating": 2157,
        "name": "player1",
        "id": "player1"
      },
      {
        "color": "black",
        "rating": 2079,
        "name": "player2",
        "id": "player2"
      }
    ],
    "pgn": "e4 d5 exd5 Qxd5 Nc3 Qa5 d4 Nf6 Nf3 Bg4 Be2 Nbd7 O-O c6 h3 Bh5 Re1 e6 Bd2 Bb4 a3 Bxc3 Bxc3 Qc7 Ne5 Bg6 Bf3 Nd5 Bd2 Nxe5 dxe5 O-O-O c4 Ne7 Qe2 Bd3 Qe3 b6 Bb4 Nf5 Qc1 c5 Bc3 Bxc4 b4 Nd4 Bd1 Nb3 Bxb3 Bxb3 bxc5 Qxc5 Qf4 Qxc3 Rac1 Bc2 Qxf7 Rhf8 Qxe6+ Kb8 Qa2 Rxf2",
    "clock": "10+0"
  },
  "puzzle": {
    "id": "ioglh",
    "rating": 1947,
    "plays": 22487,
    "solution": [
      "g1f2",
      "c3d4",
      "f2g3"
    ],
    "themes": [
      "middlegame",
      "short",
      "advantage",
      "hangingPiece",
      "defensiveMove"
    ],
    "fen": "1k1r4/p5pp/1p6/4P3/8/P1q4P/Q1b2rP1/2R1R1K1 w - - 0 1",
    "lastMove": "f8f2",
    "initialPly": 61
  }
}
"""#

    static let chessCom = #"""
{
  "title": "Eviction Notice",
  "url": "https://www.chess.com/daily/2026-11-11",
  "publish_time": 1794384000,
  "fen": "6k1/4rb2/3b1R1Q/p6p/2pq3r/P2n2NP/1P4P1/5R1K w - - 0 1",
  "pgn": "[White \"Composer\"]\n[Black \"Daily Puzzle Inspiration\"]\n[Result \"*\"]\n[FEN \"6k1/4rb2/3b1R1Q/p6p/2pq3r/P2n2NP/1P4P1/5R1K w - - 0 1\"]\n\n1. Rg6+ Bxg6 2. Rf8# *",
  "image": "https://www.chess.com/dynboard?fen=6k1/4rb2/3b1R1Q/p6p/2pq3r/P2n2NP/1P4P1/5R1K%20w%20-%20-%200%201&size=2"
}
"""#
}
