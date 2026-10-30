---
paths:
  - "ops/vflab/**"
---

# vflab installer

- The stick erases the SATA SSD + both NVMe drives and runs with nobody at the console ⇒ a change ships only after, on the built ISO: `test/vm.sh bios fresh` + `uefi fresh` → `check-installed.sh` 0 failures on both → reboot with the stick attached (its GRUB forwards to the installed `/boot`) + cold boot with `NOUSB=1`, 0 failed units each. vflab boots legacy BIOS; UEFI stays tested for a firmware change.
- Fail closed: `early.sh` + `late.sh` exit non-zero rather than guess ⇒ Subiquity stops before (early) or without rebooting (late), the live session stays on SSH (`root@` with `authorized_keys`, static .241).
- `build.sh` validates `autoinstall.yaml` against `autoinstall-schema.json` (Subiquity's) + command-list types: a YAML plain scalar holding `: ` parses as a mapping, which the installer rejects as "Malformed autoinstall"; fired on that planted `error-commands` entry (rc 1).
- Re-arming firmware fall-through does not work: SeaBIOS boots only its first disk, OVMF finds the El Torito image with the GPT zeroed ⇒ the stick stays bootable and forwards (`grub.cfg` prelude: `search --file /vflab-installed`).
- Casper waits for ENTER at reboot on removable media unless `noprompt` (kernel line) or `/run/casper-no-prompt` (`early.sh`).
- Secrets never enter the repo: the console password hash is generated from `$VFLAB_CONSOLE_PASSWORD_FILE` at build; `authorized_keys` = public key alone.
