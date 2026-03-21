#!/usr/bin/env bash
# Run Meltano from agro-protect/.venv (not uv tool). Pass any meltano args.
# Example:  cd extraction && ./scripts/run_elt.sh --environment=prod run tap-agro target-bigquery
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACTION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$EXTRACTION_DIR/.." && pwd)"
MELTANO_BIN="${REPO_ROOT}/.venv/bin/meltano"
if [[ ! -x "$MELTANO_BIN" ]]; then
  echo "Missing ${MELTANO_BIN}. Run: ./extraction/scripts/setup-local.sh" >&2
  exit 1
fi
cd "$EXTRACTION_DIR"
exec "$MELTANO_BIN" "$@"
