#!/usr/bin/env bash
# Root normalization at the builder process boundary, then real absolute/relative cache hits.
# Optional wrapper = regression control on a previous revision; no clone/build for its red case.
set -euo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
wrapper="${1:-$root/tools/build-capsule.sh}"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/tools"
cp "$wrapper" "$work/tools/build-capsule.sh"
cat >"$work/tools/capsule.py" <<'PY'
import os
import sys
from pathlib import Path
root = Path(os.environ["FVAPI_CAPSULE_ROOT"])
if not root.is_absolute() or root != root.expanduser().resolve():
    print("capsule-root: root is not canonical at builder entry", file=sys.stderr)
    sys.exit(1)
print(root)
PY
# shellcheck disable=SC2088  # The builder, not the caller's shell, expands this literal tilde.
for configured in ./capsules "$work/./capsules" '~/gate/capsules'; do
    FVAPI_CAPSULE_ROOT="$configured" bash "$work/tools/build-capsule.sh" >/dev/null
done
cd -- "$root"
parent="$(python3 -I -c 'import os; from pathlib import Path; print(Path(os.environ.get("FVAPI_CAPSULE_ROOT", str(Path.home()/"gate/capsules"))).expanduser().resolve())')"
relative="$(python3 -I -c 'import os,sys; print(os.path.relpath(sys.argv[1]))' "$parent")"
absolute_hit="$(FVAPI_CAPSULE_ROOT="$parent" bash tools/build-capsule.sh)"
relative_hit="$(FVAPI_CAPSULE_ROOT="$relative" bash tools/build-capsule.sh)"
[[ "$absolute_hit" == "$relative_hit" ]] || {
    printf 'capsule-root: absolute and relative roots selected different capsules\n' >&2
    exit 1
}
printf 'capsule-root: canonical entry + absolute/relative revalidation agree: %s\n' "$absolute_hit"
