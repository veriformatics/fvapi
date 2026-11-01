#!/usr/bin/env bash
# Re-pins one tool in tools/tools.lock to a release: its linux-x86_64 asset URL + the sha256 digest
# GitHub records for it (vflab + GitHub's runners are linux-x86_64). A Renovate PR bumps the version
# column alone; this rewrites the line. Usage: tools/pin-tool.sh <name> <version>
set -euo pipefail

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
lock="$root/tools/tools.lock"
name="${1:?usage: pin-tool.sh <name> <version>}"
version="${2:?usage: pin-tool.sh <name> <version>}"

repo="$(awk -v n="$name" '$1 == n { sub(/^https:\/\/github.com\//, "", $5); split($5, p, "/"); print p[1] "/" p[2]; exit }' "$lock")"
if [[ -z "$repo" ]]; then
    printf 'pin-tool: %s is not in %s\n' "$name" "$lock" >&2
    exit 2
fi
release="$(curl -fsSL "https://api.github.com/repos/$repo/releases/tags/v$version" ||
    curl -fsSL "https://api.github.com/repos/$repo/releases/tags/$version")"
line="$(jq -r --arg n "$name" --arg v "$version" '.assets[]
    | select(.name | test("linux.*(x86_64|amd64|x64).*tar.gz$"))
    | "\($n) \($v) linux-x86_64 \(.digest | sub("^sha256:"; "")) \(.browser_download_url)"' <<<"$release")"
if [[ "$(grep -c . <<<"$line")" -ne 1 ]]; then
    printf 'pin-tool: expected one linux-x86_64 tar.gz asset for %s %s, found:\n%s\n' "$name" "$version" "$line" >&2
    exit 1
fi
{
    grep -v -E "^$name " "$lock"
    printf '%s\n' "$line"
} | awk '/^#/ { print; next } { print | "sort" }' >"$lock.new"
mv "$lock.new" "$lock"
printf 'pin-tool: %s pinned to %s\n' "$name" "$version"
