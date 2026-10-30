#!/usr/bin/env bash
# Builds out/vflab-autoinstall.iso from the verified Ubuntu ISO: /autoinstall.yaml + /vflab/ scripts +
# a GRUB entry that boots straight into the unattended install. Boot records are replayed from the
# original (BIOS El Torito + grub2 MBR, UEFI El Torito + appended ESP, GPT).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
iso=$here/dl/ubuntu-26.04.1-live-server-amd64.iso
password_file=${VFLAB_CONSOLE_PASSWORD_FILE:?"set VFLAB_CONSOLE_PASSWORD_FILE (CLAUDE.local.md names it)"}
out=$here/out
rm -rf "$out" && mkdir -p "$out/root/vflab"

key=$(head -n1 "$here/authorized_keys")
case "$key" in ssh-*) ;; *) echo "authorized_keys holds no SSH public key" >&2; exit 1 ;; esac
hash=$(tr -d '\n' < "$password_file" | openssl passwd -6 -stdin)
iso_id="$(basename "$iso") sha256 $(sha256sum "$iso" | cut -c1-16) build $(date -u +%FT%TZ)"

sed -e "s|@CONSOLE_HASH@|$hash|" -e "s|@CONTROLLER_KEY@|$key|" \
  "$here/src/autoinstall.yaml.in" > "$out/root/autoinstall.yaml"
grep -q '@CONSOLE_HASH@\|@CONTROLLER_KEY@' "$out/root/autoinstall.yaml" && { echo "placeholder left" >&2; exit 1; }
# Subiquity's schema (canonical/subiquity autoinstall-schema.json) + the type checks it leaves open.
uv run -q --no-project --with pyyaml --with jsonschema python -I - "$out/root/autoinstall.yaml" "$here/autoinstall-schema.json" <<'PY'
import json, sys, yaml, jsonschema
ai = yaml.safe_load(open(sys.argv[1]))["autoinstall"]
jsonschema.validate(ai, json.load(open(sys.argv[2])))
for k in ("early-commands", "late-commands", "error-commands"):
    assert all(isinstance(c, str) for c in ai[k]), k
lay = ai["storage"]["layout"]
assert lay["name"] == "lvm" and "password" not in lay and lay["match"] == {"path": "@SATA_DISK@"}
assert ai["identity"]["password"].startswith("$6$") and ai["ssh"]["authorized-keys"][0].startswith("ssh-rsa ")
print("autoinstall.yaml: schema + type checks pass")
PY
cp "$here/src/vflab/early.sh" "$here/src/vflab/late.sh" "$out/root/vflab/"
printf '%s\n' "$key" > "$out/root/vflab/authorized_keys"
printf '%s\n' "$iso_id" > "$out/root/vflab/iso-id"

xorriso -osirrox on -indev "$iso" -extract /boot/grub/grub.cfg "$out/grub.cfg.orig" 2>/dev/null
chmod u+w "$out/grub.cfg.orig"
sed -e 's/^set timeout=30$/set timeout=5/' \
    -e 's|menuentry "Try or Install Ubuntu Server" {|menuentry "Install vflab (erases the SATA SSD and both NVMe drives)" {|' \
    -e 's|linux  /casper/vmlinuz  --- *$|linux  /casper/vmlinuz autoinstall noprompt ---|' \
    "$out/grub.cfg.orig" > "$out/body.cfg"
# Once installed, firmware may still pick this stick (SeaBIOS boots only its first disk; OVMF finds the
# El Torito image even with the GPT zeroed) → the stick's GRUB hands over to the installed /boot.
cat - "$out/body.cfg" > "$out/root/grub.cfg" <<'EOF'
insmod part_gpt
insmod part_msdos
insmod ext2
if search --no-floppy --file --set=vflab_boot /vflab-installed; then
  set root=$vflab_boot
  configfile ($vflab_boot)/grub/grub.cfg
fi

EOF
if ! grep -q 'set timeout=5' "$out/root/grub.cfg" || ! grep -q 'vmlinuz autoinstall noprompt ---' "$out/root/grub.cfg"; then
  echo "grub.cfg edit did not apply" >&2; exit 1
fi

xorriso -indev "$iso" -outdev "$out/vflab-autoinstall.iso" \
  -map "$out/root/autoinstall.yaml" /autoinstall.yaml \
  -map "$out/root/vflab" /vflab \
  -map "$out/root/grub.cfg" /boot/grub/grub.cfg \
  -boot_image any replay 2> "$out/xorriso.log"
sha256sum "$out/vflab-autoinstall.iso" | tee "$out/vflab-autoinstall.iso.sha256"
