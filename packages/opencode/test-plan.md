# Test runner plan — packages/opencode

## Goal

Run the full `bun test` suite (724 files) as a set of **retryable batches** with
file-level concurrency, capturing every batch's output to logs plus a
machine-readable summary.

## Why batches

- A full serial run takes hours and can hang. Observed hang:
  `test/kilocode/background-process.test.ts` leaves orphaned fixture processes
  (`opencode-test-*/persistent.mjs`, `isolated.mjs`) that keep the runner alive
  forever after the test times out.
- With batches, a hung/failed subset is killed and retried in isolation without
  losing the rest of the results.

## Environment facts

- bun 1.3.14 at `C:\Users\gcn_d\AppData\Roaming\npm\node_modules\bun\bin\bun.exe`
- Test files under `test/` by directory:

| dir | files | dir | files |
|---|---|---|---|
| kilocode | 456 | mcp | 10 |
| cli | 59 | acp | 10 |
| server | 50 | provider | 8 |
| tool | 23 | project | 8 |
| session | 21 | config | 7 |
| plugin | 16 | effect | 6 |
| util | 12 | lsp | 5 |
| agent / permission | 3 / 3 | account / skill / storage / control-plane | 2 each |
| 17 single-file dirs | 1 each | 2 root-level files | — |

- bun test features used: `--parallel N` (N worker processes, implies
  `--isolate`), positional substring patterns (union of matches), `--shard=i/n`
  (stable split of the matched set).

## Batches

| batch | pattern(s) | shard | ~files |
|---|---|---|---|
| kilocode-1 | kilocode | 1/3 | ~152 |
| kilocode-2 | kilocode | 2/3 | ~152 |
| kilocode-3 | kilocode | 3/3 | ~152 |
| cli | cli | — | 59 |
| server | server | — | 50 |
| tool | tool | — | 23 |
| session | session | — | 21 |
| plugin-util | plugin util | — | ~28 |
| mcp-acp | mcp acp | — | ~20 |
| core-config | project provider config effect | — | ~29 |
| services | lsp agent permission account skill storage control-plane | — | ~18 |
| misc | snapshot filesystem share auth v2 suggestion background question ide patch installation image git fixture format bun permission-task event-manifest | — | ~21 |

## Execution (run-tests.ps1)

- Batches run **sequentially**; inside a batch, files run in `--parallel` worker
  processes (default 4, `-Parallel` to change).
- Per-batch hard wall timeout (default 30 min, `-BatchTimeoutMin` to change).
  On timeout the whole process tree (workers + spawned fixtures) is killed, the
  batch is marked `timeout`, and the run continues with the next batch.
- After each batch, leftover `opencode-test-*` bun fixture processes are killed.
- Retry a subset: `powershell -NoProfile -File run-tests.ps1 -Batches kilocode-2,cli`

## Outputs (test-results/)

- `batch-<name>.log` / `batch-<name>.err.log` — full stdout/stderr per batch
- `summary.tsv` — batch, status (pass/fail/timeout), pass count, fail count,
  duration, log path

## Reading results

- Pass/fail counts are computed by counting `(pass)` / `(fail)` lines in the
  combined batch output; bun's final `N pass / M fail` summary is also in the log.
- Failures to analyze live in the `batch-*.log` files; grep `(fail)` for the list.

## Known hazards / notes

- Patterns are **substring** matches. Short dir names (`git`, `auth`, `question`,
  `bun`, `image`, …) can also match files in other dirs (e.g. `auth` matches
  `test/mcp/oauth-*`). Such files run in two batches — harmless duplication,
  never a miss.
- `--parallel` implies `--isolate`, so leaked handles from one file cannot
  contaminate another.
- Port collisions between concurrently running test files are possible with
  higher `-Parallel`; drop to 2 if flaky server tests appear.
- Local artifacts (gitignored): `test-results/`, `test-output.log`.
