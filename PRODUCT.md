# Knightbar

<!-- impeccable:product-schema 1 -->

## Platform

macos

Native macOS 14+ application built with SwiftUI and AppKit, for Apple Silicon and Intel. This is a macOS product, not an iOS app or a website. The Impeccable platform vocabulary does not currently list macOS; this record uses the actual platform rather than misclassifying it.

## Users

Both audiences have equal priority, as confirmed by the owner:

- Casual players taking short chess breaks.
- Experienced players managing daily puzzles and correspondence games.

## Product Purpose

Make chess available from the Mac's menu bar: play a local game, solve a daily puzzle, or attend to an online turn without opening a full chess application first.

## Positioning

The product combines offline Stockfish play, daily puzzles, and online turn awareness in one menu-bar companion. Lichess correspondence moves can be played inside the app; Chess.com games open on the provider's website.

## Operating Context

- A menu-bar knight opens a compact popover; the app has no Dock icon.
- Play, Puzzle, and Online are the existing primary modes.
- A dot and optional notifications indicate waiting online turns.
- Local games resume from saved state after restart.
- The menu-bar workflow remains central. An optional larger game window is permitted by the owner but is not implemented in the current interface.

## Capabilities and Constraints

- Offline games against bundled Stockfish, with strength, colour, and thinking-time settings; two-player games on one board.
- Daily puzzles from Lichess or Chess.com, solution checking, hints, and remembered solves.
- Lichess login, correspondence games, challenges, and game actions.
- Read-only Chess.com daily-game discovery by public username; moves are made on Chess.com.
- Local storage for games, settings, and puzzle history; Lichess credentials are kept in the macOS keychain.
- No telemetry. Network services are limited to Lichess, Chess.com, and GitHub release checks, as documented in README.md.
- Fair play: no engine, evaluation, or hints in Lichess games. Stockfish is used for local computer games.
- Existing GPL-3.0 licensing and third-party notices must be preserved.
- Larger-window behaviour, accessibility acceptance criteria, and any expansion beyond these capabilities remain open decisions.

## Brand Commitments

- Product name: Knightbar.
- Existing app copy and project material are in English.
- Preserve truthful provider attribution and avoid implying affiliation with Lichess or Chess.com.

## Evidence on Hand

- README.md: existing features, installation, privacy, fair-play boundaries, and build instructions.
- App/: current native interface and app models.
- ChessCore/: chess rules, engines, clients, and automated tests.
- docs/knightbar.gif: committed demonstration recording; it predates the latest fixes and is not proof of current runtime behaviour.
- App/Assets.xcassets/: existing knight icon and chess-piece assets.
- No user research, adoption metrics, or comparative usability study has been established in this initialization.

## Product Principles

- Keep quick access from the menu bar central, with the option to expand a game when useful.
- Serve casual and experienced players equally; provide discoverable essentials and efficient repeat use.
- Preserve the distinction between local computer help and fair online play.
- Keep personal game data local and network use limited to documented features.
