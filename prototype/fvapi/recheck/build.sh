#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# Local build only; publishing requires a registry + the user's confirmation.
podman build --tag fvapi-recheck:lean-4.35.0 --file "$HERE/Containerfile" "$HERE"
