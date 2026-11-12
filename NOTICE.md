# Third-party components

Knightbar is licensed under the GNU General Public License, version 3 (see `LICENSE`).
It includes or uses the following works by others.

## "cburnett" chess pieces

The files in `App/Assets.xcassets/Pieces/` and `App/Assets.xcassets/MenuBarIcon.imageset/`
were created by Colin M.L. Burnett and are licensed under the GNU General Public License,
version 2 or later (GPLv2+).

Source: <https://github.com/lichess-org/lila/tree/master/public/piece/cburnett>

The menu bar icon is the black knight of this set, scaled down to 18 points. The app icon in
`App/Assets.xcassets/AppIcon.appiconset/` shows the white knight of this set; it is generated
by `scripts/make-app-icon.swift`.

## Stockfish

The app ships the official Stockfish 19 chess engine as a separate executable and talks to it
over the UCI protocol. Stockfish is licensed under the GNU General Public License, version 3
(GPLv3). The engine, its licence text and its list of authors are in the app bundle under
`Contents/Resources/Stockfish/`.

Source: <https://github.com/official-stockfish/Stockfish>

The binary is not stored in this repository. `scripts/fetch-stockfish.sh` downloads the
official release and verifies its checksum.

## Online services

Knightbar talks to these services, and only to these:

- **Lichess** (<https://lichess.org>): the daily puzzle, and after you log in, your
  correspondence games through the Board API. Lichess puzzles are in the public domain (CC0).
- **Chess.com** (<https://www.chess.com>): the daily puzzle and the list of daily games in
  which a given player is to move, through the Published-Data API.

Knightbar is not affiliated with Lichess or Chess.com.
