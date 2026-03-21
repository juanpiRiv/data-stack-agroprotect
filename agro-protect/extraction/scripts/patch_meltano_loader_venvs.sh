#!/usr/bin/env bash
# Tras `meltano install`, el venv aislado de target-bigquery a veces no trae pip/setuptools
# correctos: `fs` (singer-sdk) usa `pkg_resources`, que setuptools ≥82 ya no instala →
# ModuleNotFoundError. Idempotente.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PY="${ROOT}/.meltano/loaders/target-bigquery/venv/bin/python"

if [[ ! -x "$PY" ]]; then
  echo "patch_meltano_loader_venvs: omitido (no existe .meltano/loaders/target-bigquery/venv; corré meltano install con el Meltano del proyecto)."
  exit 0
fi

echo "patch_meltano_loader_venvs: asegurando pip + setuptools en venv de target-bigquery…"
if ! "$PY" -m pip --version &>/dev/null; then
  echo "patch_meltano_loader_venvs: sin pip en el venv; ensurepip…"
  "$PY" -m ensurepip --upgrade
fi
"$PY" -m pip install -q "setuptools>=70,<82"
echo "patch_meltano_loader_venvs: listo."
