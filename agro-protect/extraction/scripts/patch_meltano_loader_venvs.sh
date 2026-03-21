#!/usr/bin/env bash
# After `meltano install`, the isolated target-bigquery venv sometimes lacks pip/setuptools
# versions `fs` (singer-sdk) needs for `pkg_resources`; setuptools ≥82 no longer ships it →
# ModuleNotFoundError. Idempotent.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="${ROOT}/.meltano/loaders/target-bigquery/venv/bin/python"

if [[ ! -x "$PY" ]]; then
  echo "patch_meltano_loader_venvs: skipped (no .meltano/loaders/target-bigquery/venv; run meltano install with the project Meltano)."
  exit 0
fi

echo "patch_meltano_loader_venvs: ensuring pip + setuptools in target-bigquery venv…"
if ! "$PY" -m pip --version &>/dev/null; then
  echo "patch_meltano_loader_venvs: no pip in venv; ensurepip…"
  "$PY" -m ensurepip --upgrade
fi
"$PY" -m pip install -q "setuptools>=70,<82"
echo "patch_meltano_loader_venvs: done."
