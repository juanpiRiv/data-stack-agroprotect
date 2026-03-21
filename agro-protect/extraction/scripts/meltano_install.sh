#!/usr/bin/env bash
# Prefer this over bare `meltano install`: ensures pip + setuptools<82 for singer-sdk/pkg_resources (see patch script).
set -euo pipefail
cd "$(dirname "$0")/.."
meltano install "$@"
./scripts/patch_meltano_loader_venvs.sh
