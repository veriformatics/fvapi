#!/usr/bin/env bash
# Runs the fvapi CLI on vflab (the user-ruled run host): `bash prototype/fvapi/fvapi-on-vflab.sh catalog`.
# Non-interactive SSH lacks ~/.local/bin (uv) + ~/.elan/bin (lean) on PATH; the vflab host key lives in ops/.
set -euo pipefail
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
exec ssh -o BatchMode=yes -o UserKnownHostsFile="$root/ops/vflab/vflab_known_hosts" offload@192.168.40.241 \
  "export PATH=\$HOME/.local/bin:\$HOME/.elan/bin:\$PATH; cd fvapi-proto && uv run -q fvapi $(printf '%q ' "$@")"
