# Formal validation log

Run date: 2026-07-18. This log records the bounded checks completed during the
formal-model review fix. It is not a V5 pass: the general quick model did not
complete within its practical cap, the final commit-cap TLC rerun was blocked
before exploration, the timer quick model was not run after the final edits,
and the expanded model was intentionally not started.

## Toolchain

- TLA+ tools: TLC 2.19, revision `5a47802`, 2024-08-08 release.
- `tla2tools.jar` SHA-256:
  `936a262061c914694dfd669a543be24573c45d5aa0ff20a8b96b23d01e050e88`.
- Java: OpenJDK 11.0.31, Ubuntu build
  `11.0.31+11-post-1ubuntu1-22.04.2-Ubuntu`.
- TLC used the breadth-first checker and the `MSBDiskFPSet` implementation.

The JAR was downloaded to `/tmp` and is not part of the repository.

## Semantic parsing

SANY semantic processing completed with exit status 0 for:

- `RelativisticRaft.tla`;
- `TimerAdaptation.tla`;
- `CommitCapRegression.tla`; and
- `CoverageTrace.tla`.

`CommitCapRegression.tla` was reparsed after
`OldLengthRuleCounterexample` became a configured temporal property. That final
SANY run completed with exit status 0.

## Completed focused checks

### Prior commit-cap reachability run (superseded)

Then-current configuration: `models/CommitCapRegression.cfg` (`MaxTerm = 3`,
`MaxLogLength = 3`, `MaxInFlight = 3`), before the negative-control temporal
property was configured.

- 13 states generated;
- 13 distinct states;
- complete-state-graph depth 7;
- 0 states left on the queue;
- the forced phase sequence reached its final state; and
- no configured error was reported.

This completed run established reachability of the forced stale-suffix repair
and the fixed outcome: the one-entry RPC advanced the follower only to index 1
and preserved `CommittedPrefixPresent`. It was executed before
`OldLengthRuleCounterexample` was added to the configuration, so it is retained
only as prior reachability evidence. It is **not** a completed check of the
current commit-cap configuration and is not an exhaustive check of all
three-entry Raft executions.

### Coverage/non-vacuity trace

Configuration: `models/CoverageTrace.cfg` (`MaxTerm = 1`,
`MaxLogLength = 1`, `MaxInFlight = 8`).

- 1,496 states generated;
- 1,232 distinct states;
- complete-state-graph depth 17;
- 0 states left on the queue;
- the temporal completion property was checked over the complete focused state
  space; and
- no invariant, action-property, or liveness error found.

The forced trace reached election, replication, quorum commit, application by
two processes, crash, and restart. It demonstrates non-vacuous exercise of
those paths, not general safety.

## Incomplete checks

### Final commit-cap regression

The current `OldLengthRuleCounterexample` property requires every fair forced
regression behavior to reach phase 6 and demonstrate all of the following in
the same state:

- the fixed RPC-covered-index rule committed only index 1;
- the superseded `Len(merged)` rule would compute index 2; and
- the follower's retained entry at index 2 differs from the globally committed
  entry at that index.

The final one-worker TLC rerun parsed and semantically processed the modules,
then failed before state exploration because the execution sandbox denied
TLC's localhost worker socket (`java.rmi.server.ExportException`, caused by
`java.net.SocketException: Operation not permitted`). A requested escalated
retry was not launched because the execution service reported an account usage
limit. Therefore the final run has no state statistics or model-checking result
and is **not a pass**. The current configuration must be rerun when TLC local
worker execution is available.

### General configurations

`models/Raft3Quick.cfg` was run with four workers and an external 30-second
wall-time cap. It did not complete. The last emitted progress record reported:

- search depth 17;
- 432,393 states generated;
- 67,364 distinct states;
- 27,072 states still queued; and
- no violation reported up to that progress point.

The process was terminated by the cap and emitted no complete-state or temporal
property summary. This run is **incomplete and not a pass**. “No violation so
far” is not evidence that the configured invariants hold over all reachable
states.

After the final edits:

- `models/Timer3Quick.cfg` was not model-checked, so no post-edit generated,
  distinct, depth, queue, or completion statistics exist; and
- `models/Raft3Safety.cfg` was not model-checked because its larger bounds were
  expected to exceed the practical review budget.

Accordingly, publication gate V5 remains open. A future validation report must
complete the declared configurations (or preregister smaller, explicitly
scoped configurations), retain full logs, and replace rather than reinterpret
the incomplete status above.

## Reproducible rerun procedure

The repository now contains `scripts/formal_validation.py` and the pinned
`formal/validation/validation_manifest.json`. Future checks should use that
harness so every command has an explicit cap and isolated state directory and
so raw logs, hashes, versions, and classifications are archived consistently.
The classifier requires explicit TLC completion and zero queued states; exit
status zero alone is insufficient. See `README.md` and
`validation/README.md` for commands and result semantics.

Adding the harness does not change the incomplete results above and does not
close V5. A new full result directory with every declared step classified
`PASS` is required before this log can be superseded.
