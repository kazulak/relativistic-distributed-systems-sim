#!/usr/bin/env python3
"""Reproducible, fail-closed SANY/TLC validation harness.

The runner archives evidence for bounded checks. It deliberately refuses to
infer success from a process exit status alone.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path
from typing import Any, Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
FORMAL_DIR = REPO_ROOT / "formal"
MANIFEST_PATH = FORMAL_DIR / "validation" / "validation_manifest.json"
DEFAULT_JAR = FORMAL_DIR / ".tools" / "tla2tools.jar"
DEFAULT_RESULTS = FORMAL_DIR / "results"

STATE_STATS_RE = re.compile(
    r"([\d,]+) states generated,\s*([\d,]+) distinct states found,\s*"
    r"([\d,]+) states left on queue",
    re.IGNORECASE,
)
DEPTH_RE = re.compile(
    r"depth of the complete state graph search is\s+([\d,]+)", re.IGNORECASE
)
COMPLETION_MARKER = "Model checking completed. No error has been found."

BLOCKER_PATTERNS = (
    r"java\.rmi\.server\.ExportException",
    r"Listen failed on port",
    r"SocketException: Operation not permitted",
    r"OutOfMemoryError",
    r"Could not reserve enough space",
    r"No space left on device",
    r"Cannot allocate memory",
)
VIOLATION_PATTERNS = (
    r"Invariant .+ is violated",
    r"Temporal properties were violated",
    r"Deadlock reached",
    r"The behavior up to this point is:",
    r"constitutes a counter-example",
    r"Assumption .+ is false",
)
ERROR_PATTERNS = (
    r"\bError:",
    r"unexpected exception",
    r"Exception in thread",
    r"Parsing or semantic analysis failed",
    r"Cannot find source file",
    r"TLC threw",
)


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def json_write(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _matches(patterns: Iterable[str], text: str) -> list[str]:
    return [pattern for pattern in patterns if re.search(pattern, text, re.IGNORECASE | re.MULTILINE)]


def _number(value: str) -> int:
    return int(value.replace(",", ""))


def parse_tlc_statistics(text: str) -> dict[str, int | None]:
    matches = list(STATE_STATS_RE.finditer(text))
    depth_matches = list(DEPTH_RE.finditer(text))
    if not matches:
        return {
            "states_generated": None,
            "distinct_states": None,
            "states_queued": None,
            "search_depth": _number(depth_matches[-1].group(1)) if depth_matches else None,
        }
    latest = matches[-1]
    return {
        "states_generated": _number(latest.group(1)),
        "distinct_states": _number(latest.group(2)),
        "states_queued": _number(latest.group(3)),
        "search_depth": _number(depth_matches[-1].group(1)) if depth_matches else None,
    }


def classify_tlc(
    stdout: str,
    stderr: str,
    exit_code: int | None,
    timed_out: bool,
) -> dict[str, Any]:
    """Classify TLC output conservatively; explicit completion is mandatory."""
    combined = "\n".join((stdout, stderr))
    statistics = parse_tlc_statistics(combined)
    blockers = _matches(BLOCKER_PATTERNS, combined)
    violations = _matches(VIOLATION_PATTERNS, combined)
    errors = _matches(ERROR_PATTERNS, combined)
    completion_seen = COMPLETION_MARKER in combined

    if timed_out:
        status, reason = "INCOMPLETE", "wall-clock cap expired before explicit TLC completion"
    elif blockers:
        status, reason = "BLOCKED", "execution environment or resource blocker detected"
    elif violations:
        status, reason = "FAIL", "TLC reported a checked-property, assumption, or deadlock violation"
    elif errors:
        status, reason = "ERROR", "TLC emitted an error marker"
    elif exit_code in (124, 137, 143):
        status, reason = "INCOMPLETE", f"process ended with interruption-style exit code {exit_code}"
    elif not completion_seen:
        status, reason = "INCOMPLETE", "explicit TLC completion marker is absent"
    elif statistics["states_queued"] is None:
        status, reason = "INCOMPLETE", "final TLC state/queue statistics are absent"
    elif statistics["states_queued"] != 0:
        status, reason = "INCOMPLETE", "TLC completion did not report zero queued states"
    elif exit_code != 0:
        status, reason = "ERROR", f"TLC completed but process exit code was {exit_code}"
    else:
        status, reason = "PASS", "explicit completion, zero queued states, and no error markers"

    return {
        "status": status,
        "reason": reason,
        "completion_marker_seen": completion_seen,
        "statistics": statistics,
        "matched_blocker_patterns": blockers,
        "matched_violation_patterns": violations,
        "matched_error_patterns": errors,
    }


def classify_sany(
    module: str,
    stdout: str,
    stderr: str,
    exit_code: int | None,
    timed_out: bool,
) -> dict[str, Any]:
    combined = "\n".join((stdout, stderr))
    blockers = _matches(BLOCKER_PATTERNS, combined)
    errors = _matches(ERROR_PATTERNS, combined)
    marker = f"Semantic processing of module {Path(module).stem}"
    if timed_out:
        status, reason = "INCOMPLETE", "wall-clock cap expired before SANY completed"
    elif blockers:
        status, reason = "BLOCKED", "execution environment or resource blocker detected"
    elif errors:
        status, reason = "ERROR", "SANY emitted an error marker"
    elif marker not in combined:
        status, reason = "INCOMPLETE", "target module semantic-processing marker is absent"
    elif exit_code != 0:
        status, reason = "ERROR", f"SANY semantic processing ended with exit code {exit_code}"
    else:
        status, reason = "PASS", "target module was parsed and semantically processed"
    return {
        "status": status,
        "reason": reason,
        "completion_marker_seen": marker in combined,
        "matched_blocker_patterns": blockers,
        "matched_error_patterns": errors,
    }


def load_manifest(path: Path = MANIFEST_PATH) -> dict[str, Any]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != 1:
        raise ValueError("unsupported validation manifest schema")
    runs = [*manifest.get("sany_runs", []), *manifest.get("tlc_runs", [])]
    ids = [run.get("id") for run in runs]
    if None in ids or len(ids) != len(set(ids)):
        raise ValueError("validation run ids must be present and unique")
    for run in runs:
        if int(run.get("timeout_seconds", 0)) <= 0:
            raise ValueError(f"{run['id']} has no positive wall-clock cap")
        if int(run.get("max_heap_mb", 0)) <= 0:
            raise ValueError(f"{run['id']} has no positive heap cap")
        _formal_input(run["module"])
        if "config" in run:
            _formal_input(run["config"])
            if int(run.get("workers", 0)) <= 0:
                raise ValueError(f"{run['id']} has no positive worker count")
    declared = {run["config"] for run in manifest.get("tlc_runs", [])}
    checked_in = {
        str(path.relative_to(FORMAL_DIR))
        for path in (FORMAL_DIR / "models").glob("*.cfg")
    }
    if declared != checked_in:
        raise ValueError(
            "TLC manifest/config mismatch: "
            f"undeclared={sorted(checked_in - declared)}, missing={sorted(declared - checked_in)}"
        )
    return manifest


def _formal_input(relative: str) -> Path:
    candidate = (FORMAL_DIR / relative).resolve()
    try:
        candidate.relative_to(FORMAL_DIR.resolve())
    except ValueError as error:
        raise ValueError(f"formal input escapes formal directory: {relative}") from error
    if not candidate.is_file():
        raise ValueError(f"formal input does not exist: {relative}")
    return candidate


def resolve_jar(argument: str | None) -> Path:
    candidate = argument or os.environ.get("TLA2TOOLS")
    return Path(candidate).expanduser().resolve() if candidate else DEFAULT_JAR.resolve()


def verify_jar(jar: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    if not jar.is_file():
        raise FileNotFoundError(
            f"tla2tools.jar not found at {jar}; pass --jar, set TLA2TOOLS, or run fetch-tool"
        )
    actual = sha256_file(jar)
    expected = manifest["tool"]["sha256"]
    if actual != expected:
        raise ValueError(f"tla2tools.jar SHA-256 mismatch: expected {expected}, observed {actual}")
    return {
        "jar_path": str(jar),
        "release": manifest["tool"]["release"],
        "tlc_version": manifest["tool"]["tlc_version"],
        "official_url": manifest["tool"]["official_url"],
        "sha256": actual,
        "verified": True,
    }


def fetch_tool(output: Path, manifest: dict[str, Any], force: bool = False) -> dict[str, Any]:
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists() and not force:
        return verify_jar(output, manifest)
    request = urllib.request.Request(
        manifest["tool"]["official_url"],
        headers={"User-Agent": "relativistic-raft-formal-validation/1"},
    )
    temporary: Path | None = None
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            with tempfile.NamedTemporaryFile(dir=output.parent, delete=False) as stream:
                temporary = Path(stream.name)
                shutil.copyfileobj(response, stream)
        verify_jar(temporary, manifest)
        os.replace(temporary, output)
        return verify_jar(output, manifest)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def run_process(command: list[str], cwd: Path, timeout_seconds: int) -> dict[str, Any]:
    started = utc_now()
    before = time.monotonic()
    process = subprocess.Popen(
        command,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=(os.name == "posix"),
    )
    timed_out = False
    try:
        stdout_bytes, stderr_bytes = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        if os.name == "posix":
            os.killpg(process.pid, signal.SIGTERM)
        else:
            process.terminate()
        try:
            stdout_bytes, stderr_bytes = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            if os.name == "posix":
                os.killpg(process.pid, signal.SIGKILL)
            else:
                process.kill()
            stdout_bytes, stderr_bytes = process.communicate()
    return {
        "command": command,
        "started_at_utc": started,
        "finished_at_utc": utc_now(),
        "duration_seconds": round(time.monotonic() - before, 6),
        "timeout_seconds": timeout_seconds,
        "timed_out": timed_out,
        "exit_code": process.returncode,
        "stdout": stdout_bytes.decode("utf-8", errors="replace"),
        "stderr": stderr_bytes.decode("utf-8", errors="replace"),
    }


def _git_repository() -> dict[str, Any]:
    def git(*arguments: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["git", *arguments],
            cwd=REPO_ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )

    commit = git("rev-parse", "HEAD")
    status = git("status", "--porcelain")
    return {
        "root": str(REPO_ROOT),
        "git_commit": commit.stdout.strip() if commit.returncode == 0 else None,
        "git_dirty": bool(status.stdout) if status.returncode == 0 else None,
        "manifest_sha256": sha256_file(MANIFEST_PATH),
    }


def _formal_bundle_hashes() -> dict[str, Any]:
    modules = {
        path.name: sha256_file(path) for path in sorted(FORMAL_DIR.glob("*.tla"))
    }
    digest = hashlib.sha256()
    for name, value in modules.items():
        digest.update(name.encode("utf-8"))
        digest.update(b"\0")
        digest.update(value.encode("ascii"))
        digest.update(b"\n")
    return {"formal_modules": modules, "formal_bundle_sha256": digest.hexdigest()}


def _step_input_hashes(run: dict[str, Any]) -> dict[str, Any]:
    hashes = _formal_bundle_hashes()
    hashes["module_sha256"] = sha256_file(_formal_input(run["module"]))
    if "config" in run:
        hashes["config_sha256"] = sha256_file(_formal_input(run["config"]))
    return hashes


def _archive_step(
    run_dir: Path,
    run: dict[str, Any],
    kind: str,
    command: list[str],
    execution: dict[str, Any],
    classification: dict[str, Any],
    metadir: Path | None,
) -> dict[str, Any]:
    step_dir = run_dir / "steps" / run["id"]
    step_dir.mkdir(parents=True)
    stdout_path = step_dir / "stdout.log"
    stderr_path = step_dir / "stderr.log"
    stdout_path.write_text(execution.pop("stdout"), encoding="utf-8")
    stderr_path.write_text(execution.pop("stderr"), encoding="utf-8")
    (step_dir / "command.txt").write_text(
        shlex.join(command) + "\n", encoding="utf-8"
    )
    result = {
        "id": run["id"],
        "kind": kind,
        "module": run["module"],
        "config": run.get("config"),
        "workers": run.get("workers"),
        "max_heap_mb": run["max_heap_mb"],
        "status": classification["status"],
        "reason": classification["reason"],
        "command": command,
        **execution,
        **{key: value for key, value in classification.items() if key not in ("status", "reason")},
        "input_hashes": _step_input_hashes(run),
        "stdout_path": str(stdout_path.relative_to(run_dir)),
        "stderr_path": str(stderr_path.relative_to(run_dir)),
        "metadir": str(metadir) if metadir is not None else None,
    }
    json_write(step_dir / "result.json", result)
    return result


def _status_of(steps: list[dict[str, Any]]) -> str:
    precedence = ("FAIL", "ERROR", "BLOCKED", "INCOMPLETE", "PASS")
    statuses = {step["status"] for step in steps}
    return next(status for status in precedence if status in statuses)


def _summary_markdown(result: dict[str, Any]) -> str:
    lines = [
        f"# Formal validation run `{result['run_id']}`",
        "",
        f"- Scope: **{result['scope']}**",
        f"- Executed-step status: **{result['overall_status']}**",
        f"- Publication gate V5: **{result['v5_gate']}**",
        f"- Tool SHA-256 verified: `{result['tool']['sha256']}`",
        "",
        "A partial run reports only its selected commands. It cannot close V5.",
        "",
        "| Step | Kind | Status | Generated | Distinct | Queued | Depth | Reason |",
        "|---|---|---:|---:|---:|---:|---:|---|",
    ]
    for step in result["steps"]:
        stats = step.get("statistics", {})
        values = [stats.get(key) for key in (
            "states_generated", "distinct_states", "states_queued", "search_depth"
        )]
        shown = ["—" if value is None else f"{value:,}" for value in values]
        reason = step["reason"].replace("|", "\\|")
        lines.append(
            f"| `{step['id']}` | {step['kind']} | **{step['status']}** | "
            f"{shown[0]} | {shown[1]} | {shown[2]} | {shown[3]} | {reason} |"
        )
    lines.extend(("", "See each `steps/<id>/` directory for the exact command and raw logs.", ""))
    return "\n".join(lines)


def execute_validation(args: argparse.Namespace, manifest: dict[str, Any]) -> tuple[Path, dict[str, Any]]:
    jar = resolve_jar(args.jar)
    tool = verify_jar(jar, manifest)
    all_runs = [
        *(dict(run, kind="SANY") for run in manifest["sany_runs"]),
        *(dict(run, kind="TLC") for run in manifest["tlc_runs"]),
    ]
    known_ids = {run["id"] for run in all_runs}
    if args.sany_only:
        selected = [run for run in all_runs if run["kind"] == "SANY"]
    elif args.only:
        unknown = set(args.only) - known_ids
        if unknown:
            raise ValueError(f"unknown validation step ids: {sorted(unknown)}")
        selected = [run for run in all_runs if run["id"] in set(args.only)]
    else:
        selected = all_runs
    if not selected:
        raise ValueError("no validation steps selected")

    run_id = args.run_id or f"formal-{dt.datetime.now(dt.timezone.utc):%Y%m%dT%H%M%SZ}-{os.getpid()}"
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", run_id):
        raise ValueError("run id may contain only letters, digits, dot, underscore, and hyphen")
    repository = _git_repository()
    results_root = Path(args.results_dir).resolve() if args.results_dir else DEFAULT_RESULTS.resolve()
    run_dir = results_root / run_id
    if run_dir.exists():
        raise FileExistsError(f"result directory already exists: {run_dir}")
    run_dir.mkdir(parents=True)

    tool_dir = run_dir / "tool"
    tool_dir.mkdir()
    java_version = run_process([args.java, "-version"], REPO_ROOT, 10)
    tlc_help = run_process([args.java, "-cp", str(jar), "tlc2.TLC", "-help"], FORMAL_DIR, 10)
    (tool_dir / "java-version.stdout.log").write_text(java_version["stdout"], encoding="utf-8")
    (tool_dir / "java-version.stderr.log").write_text(java_version["stderr"], encoding="utf-8")
    (tool_dir / "tlc-help.stdout.log").write_text(tlc_help["stdout"], encoding="utf-8")
    (tool_dir / "tlc-help.stderr.log").write_text(tlc_help["stderr"], encoding="utf-8")
    tool["java_version_exit_code"] = java_version["exit_code"]
    tool["tlc_help_exit_code"] = tlc_help["exit_code"]

    steps: list[dict[str, Any]] = []
    for run in selected:
        metadir = None
        if run["kind"] == "SANY":
            command = [
                args.java,
                f"-Xmx{run['max_heap_mb']}m",
                "-cp",
                str(jar),
                "tla2sany.SANY",
                run["module"],
            ]
        else:
            metadir = run_dir / "state" / run["id"]
            metadir.mkdir(parents=True)
            command = [
                args.java,
                f"-Xmx{run['max_heap_mb']}m",
                "-XX:+UseParallelGC",
                "-cp",
                str(jar),
                "tlc2.TLC",
                "-workers",
                str(run["workers"]),
                "-metadir",
                str(metadir),
                "-config",
                run["config"],
                run["module"],
            ]
        execution = run_process(command, FORMAL_DIR, int(run["timeout_seconds"]))
        if run["kind"] == "SANY":
            classification = classify_sany(
                run["module"], execution["stdout"], execution["stderr"],
                execution["exit_code"], execution["timed_out"]
            )
        else:
            classification = classify_tlc(
                execution["stdout"], execution["stderr"],
                execution["exit_code"], execution["timed_out"]
            )
        steps.append(
            _archive_step(run_dir, run, run["kind"], command, execution, classification, metadir)
        )
        if metadir is not None and not args.keep_state:
            shutil.rmtree(metadir)

    selected_ids = {run["id"] for run in selected}
    full_scope = selected_ids == known_ids
    overall = _status_of(steps)
    result = {
        "schema_version": 1,
        "run_id": run_id,
        "started_at_utc": min(step["started_at_utc"] for step in steps),
        "finished_at_utc": utc_now(),
        "scope": "full" if full_scope else "partial",
        "selected_step_ids": [run["id"] for run in selected],
        "overall_status": overall,
        "v5_gate": "PASS" if full_scope and overall == "PASS" else "OPEN",
        "tool": tool,
        "host": {
            "platform": platform.platform(),
            "python_version": platform.python_version(),
            "processor": platform.processor(),
        },
        "repository": repository,
        "steps": steps,
    }
    json_write(run_dir / "result.json", result)
    (run_dir / "SUMMARY.md").write_text(_summary_markdown(result), encoding="utf-8")
    return run_dir, result


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    fetch = subparsers.add_parser("fetch-tool", help="download the pinned official tla2tools.jar")
    fetch.add_argument("--output", default=str(DEFAULT_JAR))
    fetch.add_argument("--force", action="store_true")

    verify = subparsers.add_parser("verify-tool", help="verify the pinned JAR SHA-256")
    verify.add_argument("--jar")

    subparsers.add_parser("validate-manifest", help="validate declared inputs and caps")

    run = subparsers.add_parser("run", help="execute and archive declared validation checks")
    run.add_argument("--jar", help="JAR path; otherwise TLA2TOOLS or formal/.tools is used")
    run.add_argument("--java", default="java")
    run.add_argument("--results-dir")
    run.add_argument("--run-id")
    run.add_argument("--only", action="append", help="run only this declared step id; repeatable")
    run.add_argument("--sany-only", action="store_true", help="run all declared SANY checks only")
    run.add_argument("--keep-state", action="store_true", help="retain isolated TLC metadirs")

    classify = subparsers.add_parser("classify", help="classify archived TLC output")
    classify.add_argument("--stdout", required=True)
    classify.add_argument("--stderr")
    classify.add_argument("--exit-code", type=int, required=True)
    classify.add_argument("--timed-out", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        manifest = load_manifest()
        if args.command == "fetch-tool":
            result = fetch_tool(Path(args.output), manifest, args.force)
            print(json.dumps(result, indent=2, sort_keys=True))
            return 0
        if args.command == "verify-tool":
            result = verify_jar(resolve_jar(args.jar), manifest)
            print(json.dumps(result, indent=2, sort_keys=True))
            return 0
        if args.command == "validate-manifest":
            print(f"manifest valid: {len(manifest['sany_runs'])} SANY and {len(manifest['tlc_runs'])} TLC runs")
            return 0
        if args.command == "classify":
            stdout = Path(args.stdout).read_text(encoding="utf-8")
            stderr = Path(args.stderr).read_text(encoding="utf-8") if args.stderr else ""
            result = classify_tlc(stdout, stderr, args.exit_code, args.timed_out)
            print(json.dumps(result, indent=2, sort_keys=True))
            return 0 if result["status"] == "PASS" else 1
        if args.command == "run":
            run_dir, result = execute_validation(args, manifest)
            print(f"evidence: {run_dir}")
            print(f"scope={result['scope']} status={result['overall_status']} v5={result['v5_gate']}")
            return 0 if result["overall_status"] == "PASS" else 1
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"formal-validation error: {error}", file=sys.stderr)
        return 2
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
