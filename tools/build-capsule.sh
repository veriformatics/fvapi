#!/usr/bin/env bash
# P5: public pinned fva + fvamut, acquired atomically under a cache-wide lock. stdout = path.
# FVAPI_CAPSULE_ROOT defaults outside the disposable gate workspace; CI caches this directory.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${FVAPI_CAPSULE_ROOT+x}" ]]; then
    FVAPI_CAPSULE_ROOT="$(python3 -I -c 'import os; from pathlib import Path; print(Path(os.environ["FVAPI_CAPSULE_ROOT"]).expanduser().resolve())')"
    export FVAPI_CAPSULE_ROOT
fi
exec python3 -I "$root/tools/capsule.py" "$@"
