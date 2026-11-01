#!/usr/bin/env bash
# Installs the binaries pinned in tools/tools.lock (the scanners + elan-init, CI's Lean installer:
# tools/install-lean.sh) into .tools/bin/, verifying each archive's sha256 before extracting it.
# Idempotent: a binary is kept only when its stamp names the pinned version + archive digest AND
# the installed executable still hashes to the digest recorded at install (a changed cached
# binary is reinstalled from the verified archive). Gate stages call the installed path, so an
# ambient same-named executable never stands in. Usage: tools/fetch-tools.sh [name...]
# (default: every pinned tool).
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
bin="$root/.tools/bin"
cache="$root/.tools/cache"
mkdir -p "$bin" "$cache"

case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) platform=linux-x86_64 ;;
    Linux-aarch64 | Linux-arm64) platform=linux-aarch64 ;;
    Darwin-x86_64) platform=darwin-x86_64 ;;
    Darwin-arm64) platform=darwin-aarch64 ;;
    MINGW*-x86_64 | MSYS*-x86_64) platform=windows-x86_64 ;;
    *)
        printf 'fetch-tools: unsupported platform %s-%s\n' "$(uname -s)" "$(uname -m)" >&2
        exit 2
        ;;
esac

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# `tools/pin-tool.sh` rewrites every line of a tool; one line's version alone (a Renovate edit)
# labels the old release's archive with the new version, and its digest still matches.
awk '!/^#/ && NF == 5 {
    if (($1 in v) && v[$1] != $2) { printf "fetch-tools: %s lines name versions %s and %s; re-pin with tools/pin-tool.sh\n", $1, v[$1], $2; bad = 1 }
    v[$1] = $2
    if (index($5, $2) == 0) { printf "fetch-tools: %s %s: %s does not name version %s\n", $1, $3, $5, $2; bad = 1 }
} END { exit bad }' "$root/tools/tools.lock" >&2 || exit 1

wanted=("$@")
found=0
while read -r name version plat digest url; do
    [[ -z "$name" || "$name" == \#* || "$plat" != "$platform" ]] && continue
    if [[ ${#wanted[@]} -gt 0 && ! " ${wanted[*]} " =~ \ $name\  ]]; then
        continue
    fi
    found=$((found + 1))
    stamp="$bin/.$name.stamp"
    exe="$name"
    [[ "$platform" == windows-* ]] && exe="$name.exe"
    if [[ -x "$bin/$exe" && -f "$stamp" ]]; then
        read -r s_version s_digest s_installed <"$stamp" || true
        if [[ "$s_version $s_digest" == "$version $digest" &&
            "$(sha256 "$bin/$exe")" == "${s_installed:-}" ]]; then
            continue
        fi
    fi
    archive="$cache/$(basename "$url")"
    if [[ ! -f "$archive" || "$(sha256 "$archive")" != "$digest" ]]; then
        # Bounded: a server that stalls mid-transfer fails the fetch (tools/install-lean.sh retries).
        curl -fsSL --retry 3 --connect-timeout 30 --max-time 300 -o "$archive.part" "$url"
        mv "$archive.part" "$archive"
    fi
    got="$(sha256 "$archive")"
    if [[ "$got" != "$digest" ]]; then
        printf 'fetch-tools: %s sha256 mismatch: got %s, pinned %s\n' "$name" "$got" "$digest" >&2
        rm -f "$archive"
        exit 1
    fi
    work="$(mktemp -d)"
    if [[ "$archive" == *.zip ]]; then unzip -q "$archive" -d "$work"; else tar -xzf "$archive" -C "$work"; fi
    member="$(find "$work" -type f -name "$exe" | head -n 1)"
    if [[ -z "$member" ]]; then
        printf 'fetch-tools: %s archive holds no %s binary\n' "$name" "$exe" >&2
        rm -rf "$work"
        exit 1
    fi
    install -m 0755 "$member" "$bin/$exe"
    rm -rf "$work"
    printf '%s %s %s\n' "$version" "$digest" "$(sha256 "$bin/$exe")" >"$stamp"
    printf 'fetch-tools: %s %s installed\n' "$name" "$version"
done <"$root/tools/tools.lock"

if [[ $found -eq 0 ]]; then
    printf 'fetch-tools: no pinned tool matches %s %s\n' "$platform" "${wanted[*]:-}" >&2
    exit 1
fi
