import Lake
open Lake DSL

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

lean_lib Fvapi

@[default_target]
lean_exe fvapi where
  root := `Main

lean_exe «fvapi-tests» where
  root := `Tests
