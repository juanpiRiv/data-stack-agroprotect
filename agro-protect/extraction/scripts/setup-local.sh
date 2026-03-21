#!/usr/bin/env bash
#
# Bootstrap: Python 3.11+ → agro-protect/.venv → meltano[gcs] + Meltano plugins (BQ loader patch).
#
# From anywhere:
#   ./extraction/scripts/setup-local.sh
#   bash agro-protect/extraction/scripts/setup-local.sh
#
# Optional: SETUP_LOCAL_FRESH=1  → delete and recreate .venv
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACTION_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$EXTRACTION_DIR/.." && pwd)"
VENV_DIR="${REPO_ROOT}/.venv"
MIN_PY="3.11.0"

usage() {
  cat <<'EOF'
Usage: ./scripts/setup-local.sh [--help]

Creates or reuses agro-protect/.venv, installs meltano[gcs], runs meltano_install.sh
from extraction/ (plugins + target-bigquery venv patch).

  SETUP_LOCAL_FRESH=1 ./scripts/setup-local.sh   # delete and recreate .venv
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

log() { printf '%s\n' "$*"; }
step() { printf '\n── %s ──\n' "$*"; }

check_python() {
  if ! command -v python3 &>/dev/null; then
    log "Error: python3 not found (need ${MIN_PY}+)."
    exit 1
  fi
  local current
  current="$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')"
  if [[ "$(printf '%s\n' "$MIN_PY" "$current" | sort -V | head -n1)" != "$MIN_PY" ]]; then
    log "Error: need Python ${MIN_PY}+ (found ${current})."
    exit 1
  fi
  log "Python OK (${current})"
}

ensure_venv() {
  step "Virtualenv (${VENV_DIR})"
  if [[ -d "$VENV_DIR" ]]; then
    if [[ "${SETUP_LOCAL_FRESH:-0}" == "1" ]]; then
      log "SETUP_LOCAL_FRESH=1 → removing existing .venv"
      rm -rf "$VENV_DIR"
    else
      log "Reusing .venv (recreate: SETUP_LOCAL_FRESH=1 $0)"
    fi
  fi
  if [[ ! -d "$VENV_DIR" ]]; then
    log "Creating venv…"
    python3 -m venv "$VENV_DIR"
  fi
  # shellcheck source=/dev/null
  source "${VENV_DIR}/bin/activate"
  log "Active: ${VIRTUAL_ENV}"
}

install_project_deps() {
  step "Project deps (meltano[gcs])"
  log "Upgrading pip, uv…"
  python -m pip install --upgrade pip uv
  log "Editable install [extraction]…"
  (cd "$REPO_ROOT" && uv pip install -e ".[extraction]")
  log "Meltano: $(meltano --version 2>/dev/null | head -n1 || echo '(n/a)')"
}

install_meltano_plugins() {
  step "Meltano plugins + loader patch"
  cd "$EXTRACTION_DIR"
  if [[ -x ./scripts/meltano_install.sh ]]; then
    ./scripts/meltano_install.sh
  else
    log "Warning: meltano_install.sh missing; running meltano install only."
    meltano install
    [[ -x ./scripts/patch_meltano_loader_venvs.sh ]] && ./scripts/patch_meltano_loader_venvs.sh
  fi
}

print_next_steps() {
  step "Next steps (copy this checklist)"
  log ""
  log "  1) Environment"
  log "     cd \"${REPO_ROOT}\""
  log "     cp .env.example .env"
  log "     # Edit .env: BIGQUERY_*, MELTANO_GOOGLE_APPLICATION_CREDENTIALS, optional MELTANO_STATE_BACKEND_URI"
  log ""
  log "  2) Daily ELT — standard Meltano (from agro-protect/)"
  log "     source .venv/bin/activate"
  log "     hash -r && which meltano   # must be: ${REPO_ROOT}/.venv/bin/meltano"
  log "     set -a && source .env && set +a"
  log "     cd extraction"
  log "     meltano --environment=prod run tap-agro target-bigquery"
  log ""
  log "  3) Shorter test window (dev in meltano.yml)"
  log "     # same shell as step 2, still in extraction/"
  log "     meltano --environment=dev run tap-agro target-bigquery"
  log ""
  log "  4) Optional shortcuts (same runs; auto-load .env for prod/dev)"
  log "     From agro-protect/:  ./extraction/scripts/run_prod_elt.sh"
  log "                      or  ./extraction/scripts/run_dev_elt.sh"
  log "     Custom meltano args: cd extraction && ./scripts/run_elt.sh …"
  log ""
  log "  5) Long backfill (local only): cd extraction && ./scripts/run_tap_agro_bq_yearly.sh"
  log ""
  log "  More: extraction/README.md  ·  CI: .github/workflows/data-pipeline.yml"
  log ""
}

main() {
  log "AgroProtect — extraction setup"
  check_python
  ensure_venv
  install_project_deps
  install_meltano_plugins
  step "Install finished"
  print_next_steps
}

main "$@"
