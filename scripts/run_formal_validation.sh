#!/usr/bin/env bash
set -euo pipefail

formal_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
formal_repo_root="$(cd "$formal_script_dir/.." && pwd)"

exec python3 "$formal_repo_root/scripts/formal_validation.py" run "$@"
