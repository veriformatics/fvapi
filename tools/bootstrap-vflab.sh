#!/usr/bin/env bash
# Idempotent vflab setup for fvapi's own work (user ruling: builds, gates + spikes run on vflab).
# fvapi_gate.slice = a top-level slice beside system.slice (where the service runs): finite CPU,
# memory, task + root-disk IO caps and a low CPU/IO weight, so contention resolves for the
# service at the level where the two compete. Then the packages + pinned Node the gate uses.
# The live cgroup values are read back and asserted; any mismatch fails the bootstrap.
# Usage: tools/bootstrap-vflab.sh   (FVAPI_VFLAB = ssh target; needs sudo there)
set -euo pipefail

host="${FVAPI_VFLAB:-vflab}"
ssh -o BatchMode=yes "$host" 'set -euo pipefail
root_dev=/dev/mapper/ubuntu--vg-ubuntu--lv
sudo tee /etc/systemd/system/fvapi_gate.slice >/dev/null <<UNIT
[Unit]
Description=fvapi builds, gates + spikes (the service keeps 2 of 8 CPU threads, 20 GiB + disk headroom)

[Slice]
CPUQuota=600%
CPUWeight=20
IOWeight=20
MemoryMax=40G
MemorySwapMax=0
TasksMax=4096
IOReadBandwidthMax=$root_dev 250M
IOWriteBandwidthMax=$root_dev 150M

[Install]
WantedBy=slices.target
UNIT
# The earlier nested name (a dash nests it under fvapi.slice, out of competition with system.slice).
if [ -e /etc/systemd/system/fvapi-gate.slice ]; then
    sudo systemctl stop fvapi-gate.slice 2>/dev/null || true
    sudo rm -f /etc/systemd/system/fvapi-gate.slice
fi
sudo systemctl daemon-reload
# Enabled: active from boot, so tools/vflab-run (which refuses an inactive slice) survives reboots.
sudo systemctl enable --now fvapi_gate.slice
[ "$(systemctl is-enabled fvapi_gate.slice)" = enabled ] || { echo "fvapi_gate.slice not enabled" >&2; exit 1; }
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends \
    shellcheck jq rsync curl bubblewrap python3 gcc libc6-dev >/dev/null
mkdir -p ~/gate/ws
# Node for dev tooling (Renovate config validator; the console toolchain later): a pinned release
# >= 7 days old, sha256-verified, at ~/.local/node (tools/vflab-run puts its bin on PATH).
node=v24.22.1 sum=6c172a9ab6718f7b801fb5a7bd486af2ee5e32758086a04b84fcce2aa77095e6
if [ "$(readlink ~/.local/node 2>/dev/null)" != "node-$node-linux-x64" ]; then
    mkdir -p ~/.local && cd ~/.local
    curl -fsSL --retry 3 -o node.tar.xz "https://nodejs.org/dist/$node/node-$node-linux-x64.tar.xz"
    echo "$sum  node.tar.xz" | sha256sum -c --quiet
    tar -xJf node.tar.xz && rm node.tar.xz && ln -sfn "node-$node-linux-x64" node
fi
# Assert the live parent cgroup, not the unit file.
cg=/sys/fs/cgroup/fvapi_gate.slice
# systemd applies IO limits to the whole disk behind the volume.
dev="$(lsblk -sno MAJ:MIN,TYPE "$root_dev" | awk "\$2 == \"disk\" { print \$1 }" | tr -d " ")"
want="cpu.max=600000 100000
cpu.weight=20
memory.max=42949672960
memory.swap.max=0
pids.max=4096
io.max=$dev rbps=250000000 wbps=150000000 riops=max wiops=max"
got="cpu.max=$(cat $cg/cpu.max)
cpu.weight=$(cat $cg/cpu.weight)
memory.max=$(cat $cg/memory.max)
memory.swap.max=$(cat $cg/memory.swap.max)
pids.max=$(cat $cg/pids.max)
io.max=$(cat $cg/io.max)"
if [ "$got" != "$want" ]; then
    printf "bootstrap: live limits differ\nwant:\n%s\ngot:\n%s\n" "$want" "$got" >&2
    exit 1
fi
printf "%s\n" "$got"
~/.local/node/bin/node --version'
