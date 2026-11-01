# Dependencies — pin, update path, scanner (agent-read; gate stage `deps` holds every pin to a row)

| Dependency | Pinned in | Update path | Scanner / check |
|---|---|---|---|
| `leanprover/lean4` | `lean-toolchain` (4.35.0) | Renovate custom regex manager; a bump replays the verification profile's compatibility corpus (`Decisions` → `Verification profile + gate`) and keeps replay of 4.35.0 proofs | the gate's kernel-checked build + tests; CodeQL has no Lean extractor |
| `elan-init` | `tools/tools.lock` (version + sha256) | Renovate custom manager (version column) + `tools/pin-tool.sh` (digest) | sha256 verified by `tools/fetch-tools.sh` before use |
| `actionlint` | `tools/tools.lock` | as `elan-init` | sha256 pin; it is itself the workflow linter |
| `betterleaks` | `tools/tools.lock` | as `elan-init` | sha256 pin; it is itself the secret scanner |
| `zizmor` | `tools/tools.lock` | as `elan-init` | sha256 pin; it is itself the workflow security auditor |
| `actions/checkout` | `.github/workflows/*.yml` (commit digest) | Renovate github-actions manager (`helpers:pinGitHubActionDigests`) | zizmor + actionlint; CodeQL `actions` |
| `github/codeql-action/init` | `.github/workflows/codeql.yml` (commit digest) | as `actions/checkout` | zizmor + actionlint; CodeQL `actions` |
| `github/codeql-action/analyze` | `.github/workflows/codeql.yml` (commit digest) | as `actions/checkout` | zizmor + actionlint; CodeQL `actions` |
| `node` (24.22.1, vflab dev tooling) | `tools/bootstrap-vflab.sh` (version + sha256) | manual: a release ≥ 7 days old, new sha256 from nodejs.org `SHASUMS256.txt` | sha256 verified at install |
| `renovate` (config validator) | the version named in `.claude/rules/checks.md` runs | a release ≥ 7 days old per validation | runs only as a validator |
| `hacl-star/hacl-star` (scalar SHA-2 C, `dist/gcc-compatible`) | `vendor/hacl-star/lock.json` (upstream commit + per-file sha256) | a new upstream commit → `tools/vendor-hacl.sh COMMIT` (fetches exactly that commit, writes the allowlist's raw blobs, relocks); NIST vectors + the `sha256sum` differential + the gate decide | gate stage `vendor` (tree bytes = lock); OSV commit query + the upstream advisory endpoint (declared gap: no lockfile scanner covers vendored C) |
| `shellcheck`, `jq`, `rsync`, `curl`, `bubblewrap`, `python3` | distribution packages (Ubuntu 26.04 on vflab + CI runners; `tools/bootstrap-vflab.sh`) | the distribution's security updates | not pinned: the gate reads their output, never ships them |

Lake packages: none (`lake-manifest.json` lists no package); a new package needs a row before it lands.
