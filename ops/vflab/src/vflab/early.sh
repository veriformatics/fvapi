#!/bin/sh
# Runs in the live installer before disk probing. Opens SSH for the controller, refuses to reinstall
# over an existing vflab install, pins the install disk to the one SATA disk, wipes the NVMe drives.
# Any failure exits non-zero → Subiquity stops before touching a disk; the live session stays on SSH.
set -u
LOG=/run/vflab-early.log
log() { echo "vflab-early: $*" | tee -a "$LOG" > /dev/console; }
fail() { log "ABORT: $*"; exit 1; }

touch /run/casper-no-prompt

# A shut lid would suspend the live installer mid-install.
mkdir -p /run/systemd/logind.conf.d
printf '[Login]\nHandleLidSwitch=ignore\nHandleLidSwitchExternalPower=ignore\nHandleLidSwitchDocked=ignore\n' \
  > /run/systemd/logind.conf.d/90-vflab.conf
systemctl kill -s HUP systemd-logind.service 2>> "$LOG" || log "logind reload failed"

install -d -m 700 /root/.ssh
install -m 600 /cdrom/vflab/authorized_keys /root/.ssh/authorized_keys
systemctl start ssh.service 2>> "$LOG" || systemctl start ssh.socket 2>> "$LOG" || log "ssh start failed"

media=$(findmnt -no SOURCE /cdrom 2>/dev/null)
media_disk=$(lsblk -no PKNAME "$media" 2>/dev/null | head -n1)
[ -n "$media_disk" ] || media_disk=$(basename "$media")
log "install media: $media (disk /dev/$media_disk)"
lsblk -dno NAME,TRAN,RM,SIZE,MODEL,SERIAL,TYPE | tee -a "$LOG" > /dev/console

sata=$(lsblk -dnpo NAME,TRAN,TYPE | awk '$2 == "sata" && $3 == "disk" { print $1 }')
n_sata=$(printf '%s\n' "$sata" | grep -c .)
[ "$n_sata" = 1 ] || fail "expected exactly 1 SATA disk, found $n_sata: $sata"
[ "$sata" != "/dev/$media_disk" ] || fail "the SATA disk $sata is the install media"

# Anti-loop guard: late.sh leaves /boot/vflab-installed; finding it means this stick booted again.
for part in $(lsblk -lnpo NAME,FSTYPE "$sata" | awk '$2 == "ext4" { print $1 }'); do
  mkdir -p /run/vflab-probe
  if mount -o ro "$part" /run/vflab-probe 2>/dev/null; then
    found=no
    [ -e /run/vflab-probe/vflab-installed ] && found=yes
    umount /run/vflab-probe
    [ "$found" = no ] || fail "vflab is already installed on $sata ($part); remove the stick and reboot"
  fi
done

sed -i "s|@SATA_DISK@|$sata|" /autoinstall.yaml
if grep -q @SATA_DISK@ /autoinstall.yaml || ! grep -q "path: .\{0,1\}$sata" /autoinstall.yaml; then
  fail "could not pin the install disk in /autoinstall.yaml"
fi
log "install disk pinned: $sata"

# Old LVM/md/ZFS metadata on any internal disk would auto-activate and clash with the new volume group.
vgchange -an >> "$LOG" 2>&1 || true
mdadm --stop --scan >> "$LOG" 2>&1 || true
for nvme in $(lsblk -dnpo NAME,TRAN,TYPE | awk '$2 == "nvme" && $3 == "disk" { print $1 }'); do
  log "wiping $nvme"
  for part in $(lsblk -lnpo NAME,TYPE "$nvme" | awk '$2 == "part" { print $1 }'); do
    wipefs -af "$part" >> "$LOG" 2>&1 || true
  done
  wipefs -af "$nvme" >> "$LOG" 2>&1 || fail "wipefs failed on $nvme"
  blkdiscard -f "$nvme" >> "$LOG" 2>&1 || log "blkdiscard unsupported on $nvme (signatures already wiped)"
done
log "early stage done"
