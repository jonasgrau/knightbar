# Replay performance baseline — issue #11

Measured 2026-11-14 against core revision `87bbc8f`, on Apple M1, macOS 27.2.1,
Apple Swift 6.4.2. Production chess logic was not changed.

## Reproduce

```sh
bash scripts/benchmark-replay.sh 31 42
bash scripts/benchmark-replay.sh 31 7
```

The arguments are samples per metric and deterministic random seed. ChessCore and
the benchmark are compiled separately with `-O -whole-module-optimization`, with
macOS 14 as the deployment target. The separate library boundary avoids exposing
all core implementation details to the benchmark's optimizer. Builds and temporary
saved-game files are removed when each run ends.

Each metric has three warmups and 31 timed samples. Times are synchronous wall
clock milliseconds; the CSV contains median, p95, sample count and a consumed
checksum. Fixture generation, initial validation, JSON stream-fixture construction,
and fixture hashing are outside timed regions. Replay metrics retain correctness
checks on the resulting position/moves, so they include a small validation cost.

Raw outputs, including fixture SHA-256 hashes:

- [Seed 42](replay-seed42.csv)
- [Seed 7](replay-seed7.csv)

CSV metadata lines start with `#`; skip those lines when parsing the table.

## Workloads

- **quiet-synthetic:** legal games from the standard starting position, favouring
  quiet moves to preserve pieces and branching complexity. Irreversible moves are
  preferred before the fifty-move limit; moves ending the game are rejected.
- **pawn-double-stress:** the same approach after an artificial opening of sixteen
  double pawn pushes, retaining many historical en passant positions. This stresses
  their repeated normalization in repetition checks and is not a typical opening.

Prefixes cover 80, 160, 300 and 600 plies. One full move means two plies, so the
issue's 150-move example is measured as 300 plies. All fixtures remain legal and
ongoing with automatic draws enabled. No personal games or network data are used.

## Results

Ranges below span the per-seed medians, not confidence intervals. The p95 column
is the higher of the two per-seed p95 values.

| Workload | Full moves | SavedGame restore median | Highest p95 | Lichess apply median |
|---|---:|---:|---:|---:|
| Quiet synthetic | 150 | 1.28–1.46 ms | 1.80 ms | 1.65–1.94 ms |
| Pawn-double stress | 150 | 10.08–10.16 ms | 10.80 ms | 2.46–2.54 ms |
| Quiet synthetic | 300 | 3.22–3.75 ms | 3.87 ms | 3.77–4.02 ms |
| Pawn-double stress | 300 | 21.27–21.98 ms | 25.54 ms | 4.80–7.11 ms |

The isolated legality and next-position move-generation passes each take about
0.5–0.6 ms for the quiet 150-move fixture and about 0.9 ms for the stress fixture.
They are diagnostic microbenchmarks, not an additive profiler breakdown.

For the 150-move stress fixture, replay through `Game.make` costs 10.00–10.29 ms
with automatic draws enabled, versus 1.59–1.65 ms with them disabled. This estimates
the combined overhead of automatic draw checking, including repetition,
insufficient-material and fifty-move checks. It does not isolate repetition exactly.
Small differences between separately sampled metrics may reflect timing noise.

`LichessGame.apply` already uses `automaticDraws: false`; changes limited to
repetition checking would not improve that replay path. It does perform extra
legal-move lookup to resolve UCI strings before `Game.make` validates them again.

## Decision and limits

Defer a move-legality rewrite. These measurements do not establish a noticeable
problem at 150 full moves. The extreme 300-move stress case has measurable overhead;
if optimization becomes justified, first investigate limiting repetition scans to
reversible history and the same side to move, guarded by the existing draw tests.

These are synthetic, warm-run core measurements on one Apple Silicon machine,
not end-to-end popover/startup latency, user-session traces, cold-disk performance,
or Intel results. The file-load metric includes warm-cache disk reads, JSON decoding
and restoration because the fixture was saved immediately before the warmups.
Scheduling noise is visible in some tails; for example, one 600-ply stress
`make-draws-on` p95 was 41.49 ms. Do not infer production latency guarantees from
the medians or treat the generated games as a sample of player behaviour.
