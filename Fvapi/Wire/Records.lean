import Fvapi.Wire.Model
import Fvapi.Wire.Query

namespace Fvapi.Wire

open Fvapi.Json

namespace Record

def toValue {schema : Schema} (record : Record schema) : Value := record.value

/-- A conversion into a typed record must establish its full refinements and normalization. -/
def ofValue? (schema : Schema) (v : Value) : Option (Record schema) :=
  if h : HasShape schema v ∧ HasRefinements schema v ∧ project schema v = v then
    some ⟨v, h.1, h.2.1, h.2.2⟩
  else none

def decode? (schema : Schema) (v : Value) (strict : Bool := false) : Option (Record schema) := do
  let normalized ← decodeValue schema v strict
  ofValue? schema normalized

def field? {schema : Schema} (record : Record schema) (name : String) : Option Value :=
  record.value.get? name

end Record

-- Schema indexing prevents exchanging records that happen to share their JSON representation.
abbrev EntryRef := Record entryRef
abbrev RowRef := Record rowRef
abbrev Keys := Record keys
abbrev BundleRef := Record bundleRef
abbrev Subject := Record subject
abbrev Target := Record target
abbrev Checker := Record checker
abbrev EntrySummary := Record entrySummary
abbrev EntryRevision := Record entryRevision
abbrev Matches := Record matchesRecord
abbrev KeyMatch := Record keyMatch
abbrev Certificate := Record certificate
abbrev Verification := Record verification
abbrev Attempt := Record attempt
abbrev Row := Record row
abbrev KernelStatus := Record kernelStatus
abbrev Receipt := Record receipt
abbrev Answer := Record answer
abbrev RequestPackage := Record requestPackage
abbrev RequestBody := Record requestBody
abbrev AdmitBody := Record admitBody
abbrev ErrorBody (codes : List String) := Record (errorBody codes)
abbrev RowState := Record rowState
abbrev Coverage := Record coverage
abbrev Verdict := Record verdict
abbrev AdmissionCause := Record admissionCause
abbrev Query (route : Route) := Record (querySchema (routeTable route).query)

end Fvapi.Wire
