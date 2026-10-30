#!/usr/bin/env bash
# check-installed.sh <ssh-target> [ssh options…] — verifies an installed vflab over SSH as offload.
# Prints one PASS/FAIL line per check; rc = number of failures.
# shellcheck disable=SC2016  # commands expand on the remote side
set -uo pipefail
target=$1; shift
fails=0
run() { ssh -q -o BatchMode=yes -o ConnectTimeout=5 "$@" "$target" "$cmd" 2>&1; }
check() {
  local name=$1 want=$2; cmd=$3
  local got; got=$(run "${opts[@]}")
  if printf '%s' "$got" | grep -qE "$want"; then echo "PASS $name"; else echo "FAIL $name: $(printf '%s' "$got" | tr '\n' ' ' | cut -c1-300)"; fails=$((fails + 1)); fi
}
opts=("$@")
check hostname '^vflab$' 'hostname'
check sudo-nopasswd '^ok$' 'sudo -n true && echo ok'
check root-plain-lvm '^disk lvm part $' 'lsblk -no TYPE "$(findmnt -no SOURCE /)" -s | sort -u | tr "\n" " "'
check no-luks-anywhere '^0$' 'lsblk -no FSTYPE | grep -c crypto_LUKS'
check root-disk-sata 'sata' 'for d in $(lsblk -nso NAME,TYPE "$(findmnt -no SOURCE /)" | awk "\$2==\"disk\"{print \$1}" | tr -d "└─├│ "); do lsblk -dno TRAN /dev/$d; done'
check static-address '192\.168\.40\.241/24' 'ip -4 -br addr'
check sshd-no-password 'passwordauthentication no' 'sudo sshd -T | grep -i "^passwordauthentication"'
check lid-ignored 'HandleLidSwitch=ignore' 'cat /etc/systemd/logind.conf.d/90-vflab.conf'
check sleep-masked 'masked' 'systemctl is-enabled suspend.target 2>&1'
check grub-timeouts 'GRUB_RECORDFAIL_TIMEOUT=5' 'cat /etc/default/grub.d/90-vflab.cfg'
check install-marker '^installed ' 'cat /boot/vflab-installed'
check nvme-blank '^nvme0n1:0 nvme1n1:0$|^nvme1n1:0 nvme0n1:0$' 'for d in $(lsblk -dnpo NAME,TRAN | awk "\$2==\"nvme\"{print \$1}"); do printf "%s:%s " "$(basename $d)" "$(lsblk -nlo TYPE $d | grep -c part)"; done | sed "s/ $//"'
check late-log 'late stage done' 'sudo tail -n1 /var/log/vflab-late.log'
check failed-units '^0$' 'systemctl --failed --no-legend | wc -l'
echo "failures: $fails"
exit "$fails"
