#!/bin/sh
# Runs after a successful install, target at /target. Makes the box reach SSH after every reboot with
# nobody at its console. The stick stays bootable: its GRUB forwards to the installed system (grub.cfg).
# Any failure exits non-zero → the installer stops without rebooting; the live session stays on SSH.
set -u
LOG=/target/var/log/vflab-late.log
log() { echo "vflab-late: $*" | tee -a "$LOG" > /dev/console; }
fail() { log "ABORT: $*"; exit 1; }
intarget() { curtin in-target --target=/target -- "$@"; }

touch /run/casper-no-prompt

printf 'offload ALL=(ALL) NOPASSWD:ALL\n' > /target/etc/sudoers.d/90-offload
chmod 440 /target/etc/sudoers.d/90-offload
intarget visudo -cf /etc/sudoers.d/90-offload >> "$LOG" 2>&1 || fail "sudoers check failed"

# A laptop board: a shut lid or a power key must never suspend the server.
mkdir -p /target/etc/systemd/logind.conf.d
cat > /target/etc/systemd/logind.conf.d/90-vflab.conf <<'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
EOF
intarget systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target >> "$LOG" 2>&1 \
  || fail "masking sleep targets failed"

# Ubuntu's recordfail waits at the GRUB menu after an unclean shutdown; cap every wait.
cat > /target/etc/default/grub.d/90-vflab.cfg <<'EOF'
GRUB_TIMEOUT_STYLE=menu
GRUB_TIMEOUT=3
GRUB_RECORDFAIL_TIMEOUT=5
EOF
intarget update-grub >> "$LOG" 2>&1 || fail "update-grub failed"

printf 'installed %s from %s\n' "$(date -u +%FT%TZ)" "$(cat /cdrom/vflab/iso-id 2>/dev/null)" > /target/boot/vflab-installed

log "late stage done"
