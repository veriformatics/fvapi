#!/usr/bin/env bash
# Relock public fva source + dependency/canary pins. Run through tools/vflab-run.
# No argument = byte-identical regeneration; COMMIT = an explicit pin update.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 -I "$root/tools/pin-capsule.py" "$@"
