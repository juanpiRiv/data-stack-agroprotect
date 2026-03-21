#!/usr/bin/env bash
# Dev ELT: short window from meltano.yml. Sources agro-protect/.env if present.
# Run from agro-protect/:  ./extraction/scripts/run_dev_elt.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACTION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$EXTRACTION_DIR/.." && pwd)"
cd "$EXTRACTION_DIR"
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.env"
  set +a
fi
export TAP_AGRO_USE_OPEN_METEO="${TAP_AGRO_USE_OPEN_METEO:-false}"
exec "${SCRIPT_DIR}/run_elt.sh" --environment=dev run tap-agro target-bigquery
