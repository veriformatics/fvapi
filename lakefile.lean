import Lake
open Lake DSL System

package fvapi where
  version := v!"0.1.0"
  description :=
    "An API for formal verification: library lookups, bundles the caller re-checks, " ++
    "proven checkers."
  keywords := #["formal-verification", "lean", "api"]
  license := "Apache-2.0"
  licenseFiles := #["LICENSE"]
  testDriver := "«fvapi-tests»"
  leanOptions := #[⟨`autoImplicit, false⟩, ⟨`relaxedAutoImplicit, false⟩, ⟨`warningAsError, true⟩]

/-! ## Native code: HACL*'s verified SHA-256 + fvapi's shim (`docs/contracts/U3-codecs.md` S2) -/

def haclDist : FilePath := "vendor" / "hacl-star" / "dist"

/-- `-I` roots + the toolchain compiler's own flags: host paths, so weak (a moved checkout must
not rebuild); their content is traced through `cTrace`. The toolchain's clang ships no libc
headers (`-nostdinc`) and HACL's headers need some (`string.h`, `endian.h`): the system's glibc
headers (`libc6-dev`) follow clang's builtin ones. -/
def cWeakArgs (pkg : Package) : FetchM (Array String) := do
  let roots := #[haclDist / "gcc-compatible", haclDist / "karamel" / "include",
    haclDist / "karamel" / "krmllib" / "dist" / "minimal"]
  return (roots.flatMap fun r => #["-I", (pkg.dir / r).toString]) ++
    #["-I", (← getLeanIncludeDir).toString] ++ (← getLeanInstall).ccFlags ++
    #["-isystem", "/usr/include/x86_64-linux-gnu", "-isystem", "/usr/include"]

/-- Lake traces a C source + its flags alone: every header (vendored + fvapi's) and the toolchain
(compiler + `lean.h`) join the trace, so a changed header or toolchain rebuilds the objects.
`computeFileHash`, not `fetchFileTrace`: the latter caches `<file>.hash` beside each header,
littering the byte-checked vendored tree. -/
def cTrace (pkg : Package) : JobM BuildTrace := do
  let headers := (← (pkg.dir / haclDist).walkDir) ++ (← (pkg.dir / "c").walkDir)
  let mut trace ← getLeanTrace
  for h in headers.qsort (·.toString < ·.toString) do
    if h.extension == some "h" then
      trace := trace.mix (.ofHash (← computeFileHash h) h.toString)
  return trace

input_file hacl_sha2.c where
  path := haclDist / "gcc-compatible" / "Hacl_Hash_SHA2.c"

input_file fvapi_sha256_core.c where
  path := "c" / "fvapi_sha256_core.c"

input_file fvapi_sha256.c where
  path := "c" / "fvapi_sha256.c"

/-- HACL's upstream build flags; the shim adds warnings as errors (HACL's generated C keeps its
own warning policy). -/
target hacl_sha2.o pkg : FilePath := do
  buildO (pkg.buildDir / "c" / "hacl_sha2.o") (← hacl_sha2.c.fetch) (← cWeakArgs pkg)
    #["-std=gnu11", "-O3", "-fPIC"] (← getLeanCc) (cTrace pkg)

target fvapi_sha256_core.o pkg : FilePath := do
  buildO (pkg.buildDir / "c" / "fvapi_sha256_core.o") (← fvapi_sha256_core.c.fetch)
    (← cWeakArgs pkg) #["-std=gnu11", "-O3", "-fPIC", "-Wall", "-Wextra", "-Werror"] (← getLeanCc)
    (cTrace pkg)

target fvapi_sha256.o pkg : FilePath := do
  buildO (pkg.buildDir / "c" / "fvapi_sha256.o") (← fvapi_sha256.c.fetch) (← cWeakArgs pkg)
    #["-std=gnu11", "-O3", "-fPIC", "-Wall", "-Wextra", "-Werror"] (← getLeanCc) (cTrace pkg)

input_file fvapi_fsync.c where
  path := "c" / "fvapi_fsync.c"

target fvapi_fsync.o pkg : FilePath := do
  buildO (pkg.buildDir / "c" / "fvapi_fsync.o") (← fvapi_fsync.c.fetch) (← cWeakArgs pkg)
    #["-std=gnu11", "-O3", "-fPIC", "-Wall", "-Wextra", "-Werror"] (← getLeanCc) (cTrace pkg)

target libfvapinative pkg : FilePath := do
  buildStaticLib (pkg.staticLibDir / nameToStaticLib "fvapinative")
    #[← hacl_sha2.o.fetch, ← fvapi_sha256_core.o.fetch, ← fvapi_sha256.o.fetch,
      ← fvapi_fsync.o.fetch]

/-! ## Lean targets -/

/-- `include_str` alone is not a Lake-traced input: replay must embed the current checker. -/
input_file inventory_source where
  path := "tools" / "lean" / "Inventory.lean"

lean_lib Fvapi where
  needs := #[`@/inventory_source]
  moreLinkObjs := #[libfvapinative]

/-- Audit tree (never imported by shipped code): reviewed vocabulary, closed claims, proofs. -/
lean_lib FvapiProofs where
  globs := #[.one `FvapiProofs, .submodules `FvapiSpec, .submodules `FvapiSelf,
    .submodules `FvapiProof]

@[default_target]
lean_exe fvapi where
  root := `Main

lean_exe «fvapi-tests» where
  root := `Tests

/-- Blind U2 suite: the shipped kernel policy vs an independent oracle. -/
lean_lib TestsU2 where
  globs := #[.submodules `TestsU2]

lean_exe «fvapi-tests-u2» where
  root := `TestsU2.Policy

/-- Blind U3 suite (contract + independent oracle); `TestsU3.Api` is its only implementation
import. -/
lean_lib TestsU3 where
  globs := #[.submodules `TestsU3]

lean_exe «fvapi-tests-u3» where
  root := `TestsU3.Main

/-- The oracle's crosscheck, built without the implementation adapter. -/
lean_exe «fvapi-tests-u3-oracle» where
  root := `TestsU3.OracleMain

/-- Blind U3 part B: `TestsU3B.Api` is the sole public Fsync import. -/
lean_lib TestsU3B where
  globs := #[.submodules `TestsU3B]

lean_exe «fvapi-tests-u3b» where
  root := `TestsU3B.Main
