# Formal validation log

Run date: 2026-08-25. This log supersedes the 2026-07-18 record below in full.
The declared manifest now completes end-to-end under the fail-closed harness,
and publication gate V5 is **PASS** for the checked configurations.

## Authoritative run

- Run id: `formal-v5-full-r2`
- Harness: `scripts/formal_validation.py` against
  `formal/validation/validation_manifest.json`
- Scope: **full**; executed-step status: **PASS**; V5: **PASS**
- Evidence directory: gitignored `formal/results/formal-v5-full-r2/`
  (`result.json`, per-step commands, raw logs, hashes). The tables below are a
  projection of that machine-readable record.

### Toolchain

- TLA+ tools: `tla2tools.jar` v1.7.4 (TLC 2.19, rev `5a47802`, 2024-08-08)
- SHA-256 verified by the harness:
  `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`
- Java: OpenJDK 24.0.1 (Windows); Python 3.14 host for the harness

### Results

| Step | Kind | Status | Generated | Distinct | Queued | Depth |
|---|---|---|---:|---:|---:|---:|
| `sany_relativistic_raft` | SANY | PASS | — | — | — | — |
| `sany_timer_adaptation` | SANY | PASS | — | — | — | — |
| `sany_commit_cap_regression` | SANY | PASS | — | — | — | — |
| `sany_coverage_trace` | SANY | PASS | — | — | — | — |
| `tlc_commit_cap_regression` | TLC | PASS | 13 | 13 | 0 | 7 |
| `tlc_coverage_trace` | TLC | PASS | 1,496 | 1,232 | 0 | 17 |
| `tlc_raft3_quick` | TLC | PASS | 8,893,969 | 769,727 | 0 | 35 |
| `tlc_timer3_quick` | TLC | PASS | 89,614,282 | 6,156,762 | 0 | 35 |
| `tlc_raft3_safety` | TLC | PASS | 132,953,091 | 11,560,890 | 0 | 47 |

Every TLC step shows the explicit completion sentence, zero queued states, and
no violation. The previously blocked commit-cap regression (sandbox RMI
denial) and the previously timed-out general quick model both completed on
local hardware. The non-vacuity witnesses were exercised: election,
replication, quorum commit, application by two processes, crash, restart
(`CoverageTrace`), and the stale-suffix repair regression reached its forced
final state with the negative-control property satisfied (`CommitCapRegression`).

## Cap revision record

One pre-declared cap revision was applied between runs: `tlc_timer3_quick`
was raised from 300 s to 1800 s after an intermediate full run
(`formal-20260825T121148Z-9388`) classified it INCOMPLETE at its original cap
while every other step passed. A focused rerun
(`formal-timer3-rev2`) confirmed the configuration completes explicitly, and
the authoritative full run above was executed afterwards under the revised
manifest. No other cap changed. Superseded evidence remains under its
original run id.

## What this establishes and what it does not

V5 is exhaustive only for the configured finite constants and `MaxInFlight`
bounds of each model. It is not a proof for arbitrary cluster sizes, terms,
log lengths, or values, and it says nothing about availability or detector
quality. Abstraction limits are enumerated in `README.md`. Gate-level context
and pointers live in `../docs/VALIDATION_GATES.md`.

---

# Superseded record (2026-07-18) — retained verbatim for history

Run date: 2026-07-18. This log records the bounded checks completed during the
formal-model review fix. It is not a V5 pass: the general quick model did not
complete within its practical cap, the final commit-cap TLC rerun was blocked
before exploration, the timer quick model was not run after the final edits,
and the expanded model was intentionally not started.

(…the remainder of the superseded log is preserved in repository history at
commit `19e190d`; its classifications are replaced by the authoritative run
above and are no longer current.)
