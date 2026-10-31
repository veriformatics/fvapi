#!/usr/bin/env bash
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
COMMON=$(git -C "$ROOT" rev-parse --path-format=absolute --git-common-dir)
PRIMARY=$(dirname "$COMMON")
TARGET=${FVAPI_TARGET:-offload@192.168.40.241}
KNOWN_HOSTS=${FVAPI_KNOWN_HOSTS:-$PRIMARY/ops/vflab/vflab_known_hosts}
MANIFEST=${FVAPI_SEED:-$PRIMARY/prototype/fvapi/seed.local.json}
SSH=(ssh -o BatchMode=yes -o UserKnownHostsFile="$KNOWN_HOSTS" "$TARGET")
export RSYNC_RSH="ssh -o BatchMode=yes -o UserKnownHostsFile=$KNOWN_HOSTS"
mkdir -p "$ROOT/.scratch"
TEMP=$(mktemp -d "$ROOT/.scratch/deploy.XXXXXX")
trap 'rm -rf "$TEMP"' EXIT

"${SSH[@]}" 'bash -s' <<'BOOTSTRAP'
set -euo pipefail
mkdir -p "$HOME/.local/bin" "$HOME/fvapi-proto" /srv/data/fvapi
cd "$HOME/fvapi-proto"
DOWNLOADS=$(mktemp -d "$HOME/.local/fvapi-install.XXXXXX")
trap 'rm -rf "$DOWNLOADS"' EXIT
if ! test -x "$HOME/.local/bin/uv"; then
    mkdir "$DOWNLOADS/uv"
    curl -LsSf https://astral.sh/uv/install.sh -o "$DOWNLOADS/uv/install.sh"
    UV_NO_MODIFY_PATH=1 sh "$DOWNLOADS/uv/install.sh"
fi
if ! test -x "$HOME/.elan/bin/elan"; then
    mkdir "$DOWNLOADS/elan"
    curl -sSf https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh -o "$DOWNLOADS/elan/install.sh"
    sh "$DOWNLOADS/elan/install.sh" -y --no-modify-path --default-toolchain none
fi
"$HOME/.elan/bin/elan" toolchain install leanprover/lean4:v4.35.0
"$HOME/.elan/bin/elan" default leanprover/lean4:v4.35.0
BOOTSTRAP
rsync -az --delete --exclude .venv --exclude store --exclude out --exclude seed.local.json "$HERE/" "$TARGET:fvapi-proto/"
(cd "$HERE" && uv run fvapi-seed --manifest "$MANIFEST" --store "$TEMP/store")
# Logs survive seed/deploy; a second deployment must not erase request history.
rsync -az --exclude demand.jsonl --exclude answers.jsonl "$TEMP/store/" "$TARGET:/srv/data/fvapi/"
"${SSH[@]}" 'bash -s' <<'REMOTE'
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.elan/bin:$PATH"
cd "$HOME/fvapi-proto"
uv sync --locked
mkdir -p console/variants /srv/data/fvapi/checkers
# Build every executable entry generically. Its source lives only in the private store.
uv run python - <<'PY'
import json, os, pathlib, shutil, subprocess
store = pathlib.Path('/srv/data/fvapi')
for path in store.glob('entries/*/entry.json'):
    entry = json.loads(path.read_text())
    if entry['check'] is None:
        continue
    build = store / 'checkers' / entry['id']
    build.mkdir(parents=True, exist_ok=True)
    for item in entry['closure']:
        source = path.parent / 'files' / item['path']
        target = build / item['path']
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    libdir = subprocess.check_output(['lean', '--print-libdir'], text=True).strip()
    env = {**os.environ, 'LEAN_PATH': str(build) + os.pathsep + libdir}
    for argv in entry['check']['recheck']['build']:
        subprocess.run(argv, cwd=build, env=env, check=True)
PY
sudo tee /etc/systemd/system/fvapi-proto.service >/dev/null <<UNIT
[Unit]
Description=fvapi disposable prototype
After=network.target
[Service]
User=offload
WorkingDirectory=$HOME/fvapi-proto
Environment=PATH=$HOME/.local/bin:$HOME/.elan/bin:/usr/local/bin:/usr/bin:/bin
Environment=FVAPI_STORE=/srv/data/fvapi
Environment=FVAPI_HOST=0.0.0.0
Environment=FVAPI_PORT=8441
ExecStart=$HOME/fvapi-proto/.venv/bin/fvapi-server
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable fvapi-proto.service
sudo systemctl restart fvapi-proto.service
if command -v ufw >/dev/null && sudo ufw status | grep -q '^Status: active'; then
    sudo ufw allow 8441/tcp
fi
REMOTE
HOST=${TARGET#*@}
deadline=$((SECONDS + 60))
until curl --connect-timeout 1 --max-time 2 -sf "http://$HOST:8441/v0/health"; do
    if ((SECONDS >= deadline)); then
        printf 'fvapi did not become ready within 60 seconds\n' >&2
        exit 1
    fi
    sleep 1
done
printf '\nDeployment ready: http://%s:8441/\n' "$HOST"
