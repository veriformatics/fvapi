#!/usr/bin/env bash
# write-stick.sh <serial> — writes out/vflab-autoinstall.iso to the USB stick with that serial (never by device
# name), then reads it back and compares bytes.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
iso=$here/out/vflab-autoinstall.iso
serial=${1:?"usage: write-stick.sh <stick serial> (lsblk -dno NAME,SERIAL,TRAN)"}
dev=$(lsblk -dnpo NAME,SERIAL,TRAN,RM | awk -v s="$serial" '$2 == s && $3 == "usb" && $4 == "1" { print $1 }')
[ -n "$dev" ] && [ "$(printf '%s\n' "$dev" | wc -l)" = 1 ] || { echo "stick with serial $serial not found exactly once" >&2; exit 1; }
if lsblk -nro MOUNTPOINT "$dev" | grep -q .; then echo "$dev has mounted partitions" >&2; exit 1; fi
size=$(stat -c %s "$iso")
echo "writing $iso ($size bytes) to $dev ($(lsblk -dno MODEL,SIZE "$dev"))"
sudo wipefs -aq "$dev"
sudo dd if="$iso" of="$dev" bs=4M conv=fsync oflag=direct status=none
sync
sudo blockdev --flushbufs "$dev"
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
want=$(sha256sum "$iso" | cut -d' ' -f1)
got=$(sudo head -c "$size" "$dev" | sha256sum | cut -d' ' -f1)
echo "image sha256 $want"
echo "stick sha256 $got"
[ "$want" = "$got" ] || { echo "MISMATCH" >&2; exit 1; }
echo "stick verified"
