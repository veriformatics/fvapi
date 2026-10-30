#!/usr/bin/env bash
# vm.sh <bios|uefi> <fresh|boot> — QEMU stand-in for vflab: 2 NVMe + 1 SATA + the image as a removable
# USB stick (bootindex 1, SATA 2). fresh = new disks + a fresh copy of the image; boot = reuse disks.
# SSH: bios → localhost:2222, uefi → localhost:2223. Monitor socket: <mode>/mon (screendump).
# shellcheck disable=SC2054  # commas belong to QEMU option values
set -euo pipefail
mode=$1 action=$2
here=$(cd "$(dirname "$0")" && pwd)
dir=$here/$mode
iso=$here/../out/vflab-autoinstall.iso
port=2222; [ "$mode" = uefi ] && port=2223
mkdir -p "$dir"
if [ "$action" = fresh ]; then
  rm -f "$dir"/*.img "$dir"/*.qcow2 "$dir"/vars.fd
  cp --reflink=auto "$iso" "$dir/usb.img" && truncate -s 4G "$dir/usb.img"
  qemu-img create -q -f qcow2 "$dir/sata.qcow2" 24G
  for n in 0 1; do
    truncate -s 8G "$dir/nvme$n.img"
    sgdisk -q -o -n 1:0:+512M -t 1:ef00 -n 2:0:0 -t 2:8300 "$dir/nvme$n.img"
  done
  [ "$mode" = uefi ] && cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$dir/vars.fd"
fi
usb=(-drive file="$dir/usb.img",if=none,id=usb,format=raw -device usb-storage,bus=xhci.0,drive=usb,removable=on,bootindex=1)
[ "${NOUSB:-0}" = 1 ] && usb=()
fw=()
if [ "$mode" = uefi ]; then
  fw=(-drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd
      -drive if=pflash,format=raw,file="$dir/vars.fd")
fi
exec qemu-system-x86_64 -enable-kvm -machine q35 -cpu host -smp 3 -m 6G "${fw[@]}" \
  -device ahci,id=ahci \
  -drive file="$dir/sata.qcow2",if=none,id=sata,format=qcow2 -device ide-hd,drive=sata,bus=ahci.0,bootindex=2,serial=SATA-SSD-TEST \
  -drive file="$dir/nvme0.img",if=none,id=nv0,format=raw -device nvme,drive=nv0,serial=NVME0TEST \
  -drive file="$dir/nvme1.img",if=none,id=nv1,format=raw -device nvme,drive=nv1,serial=NVME1TEST \
  -device qemu-xhci,id=xhci "${usb[@]}" \
  -netdev user,id=n0,hostfwd=tcp::"$port"-:22 -device virtio-net-pci,netdev=n0 \
  -display none -vga std -monitor unix:"$dir/mon",server,nowait
