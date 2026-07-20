# Formal-validation evidence format

`validation_manifest.json` is the executable declaration of the bounded formal
checks. It pins the official `tla2tools.jar` URL and SHA-256 and lists every
checked-in TLC configuration. Each entry declares its module, wall-clock cap,
maximum Java heap, and worker count. Manifest validation fails when a checked-in
`models/*.cfg` file is undeclared.

The runner resolves the JAR from `--jar`, then `TLA2TOOLS`, then the ignored
`formal/.tools/tla2tools.jar` cache. `fetch-tool` downloads only the pinned
[official TLA+ release](https://github.com/tlaplus/tlaplus/releases/tag/v1.7.4)
and verifies it before atomically installing it.

Each ignored `formal/results/<run-id>/` contains:

- `result.json`, conforming to `result.schema.json`;
- `SUMMARY.md`, a human-readable status table;
- tool-version stdout/stderr; and
- `steps/<id>/command.txt`, raw stdout/stderr, and per-step `result.json`.

Statuses have deliberately narrow meanings:

- `PASS`: explicit completion, zero queued states, no error markers, and exit
  status zero;
- `FAIL`: a checked invariant/property, assumption, or deadlock violation;
- `BLOCKED`: an execution-environment/resource failure such as the localhost
  RMI socket exception;
- `INCOMPLETE`: timeout, interruption, nonempty queue, or missing completion
  evidence; and
- `ERROR`: parsing, configuration, tool, or otherwise unclassified execution
  error.

The aggregate V5 gate remains `OPEN` for every partial selection. It becomes
`PASS` only when all manifest SANY and TLC entries pass in one full archived
run. Generated TLC state and downloaded JAR files are intentionally ignored and
must not be committed.
