#!/usr/bin/env bash
# Vendors HACL*'s scalar SHA-256 C (docs/contracts/U3-codecs.md S1): fetches exactly COMMIT from
# upstream git (content authenticated by the object ids; codeload tarball bytes are not stable),
# checks out the allowlist alone into vendor/hacl-star/ and rewrites vendor/hacl-star/lock.json
# (upstream, commit, per-file sha256 = the gate's pin). Idempotent.
# Usage: tools/vendor-hacl.sh [COMMIT] — no argument = re-vendor the locked commit, whose bytes
# must still equal the lock; a new COMMIT relocks (the gate + vectors then decide the bump).
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
dest="$root/vendor/hacl-star"
lock="$dest/lock.json"
upstream=https://github.com/hacl-star/hacl-star

# The scalar SHA-2 closure on x86_64 Linux with native __int128: one translation unit + the
# headers it includes, plus both licence texts.
allow=(
    LICENSE
    dist/LICENSE.txt
    dist/gcc-compatible/Hacl_Hash_SHA2.c
    dist/gcc-compatible/Hacl_Hash_SHA2.h
    dist/gcc-compatible/internal/Hacl_Hash_SHA2.h
    dist/gcc-compatible/Hacl_Streaming_Types.h
    dist/gcc-compatible/internal/Hacl_Streaming_Types.h
    dist/gcc-compatible/Hacl_Krmllib.h
    dist/gcc-compatible/internal/Hacl_Krmllib.h
    dist/karamel/include/krml/internal/types.h
    dist/karamel/include/krml/internal/target.h
    dist/karamel/include/krml/internal/compat.h
    dist/karamel/include/krml/lowstar_endianness.h
    dist/karamel/krmllib/dist/minimal/fstar_uint128_gcc64.h
    dist/karamel/krmllib/dist/minimal/FStar_UInt128.h
    dist/karamel/krmllib/dist/minimal/FStar_UInt_8_16_32_64.h
    dist/karamel/krmllib/dist/minimal/LowStar_Endianness.h
)

relock=1
if [[ $# -eq 1 ]]; then
    commit="$1"
elif [[ $# -eq 0 ]]; then
    commit="$(jq -er .commit "$lock")"
    relock=0
else
    printf 'usage: tools/vendor-hacl.sh [COMMIT]\n' >&2
    exit 2
fi
[[ $commit =~ ^[0-9a-f]{40}$ ]] || {
    printf 'vendor-hacl: COMMIT = 40 hex\n' >&2
    exit 2
}

work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT
git init -q "$work/repo"
git -C "$work/repo" remote add origin "$upstream"
git -C "$work/repo" fetch -q --depth 1 --filter=blob:none origin "$commit"
got="$(git -C "$work/repo" rev-parse FETCH_HEAD)"
[[ $got == "$commit" ]] || {
    printf 'vendor-hacl: fetched %s, wanted %s\n' "$got" "$commit" >&2
    exit 1
}

# Raw blob bytes at the commit: a checkout may rewrite them (autocrlf, attributes, filters).
mkdir -p "$work/out"
for f in "${allow[@]}"; do
    read -r mode type _ < <(git -C "$work/repo" ls-tree "$commit" -- "$f")
    if [[ ${type:-} != blob || ! ${mode:-} =~ ^100(644|755)$ ]]; then
        printf 'vendor-hacl: %s is not a regular file at %s\n' "$f" "$commit" >&2
        exit 1
    fi
    mkdir -p "$(dirname "$work/out/$f")"
    git -C "$work/repo" cat-file blob "$commit:$f" >"$work/out/$f"
done
(
    cd "$work/out"
    printf '%s\n' "${allow[@]}" | LC_ALL=C sort | while read -r f; do
        printf '%s\t%s\n' "$f" "$(sha256sum "$f" | cut -d' ' -f1)"
    done
) | jq -Rn --arg upstream "$upstream" --arg commit "$commit" '
    { upstream: $upstream, commit: $commit,
      files: (reduce (inputs | split("\t")) as $r ({}; .[$r[0]] = $r[1])) }' >"$work/out/lock.json"
if [[ $relock -eq 0 ]] && ! cmp -s "$work/out/lock.json" "$lock"; then
    printf 'vendor-hacl: commit %s no longer yields the locked bytes\n' "$commit" >&2
    diff <(jq -S . "$lock") <(jq -S . "$work/out/lock.json") >&2 || true
    exit 1
fi
rm -rf -- "$dest"
mkdir -p "$(dirname "$dest")"
mv -- "$work/out" "$dest"
printf 'vendor-hacl: %s files at %s\n' "$(jq '.files | length' "$lock")" "$commit"
