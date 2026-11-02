import FvapiProof.Wire.Model
import FvapiSpec.Wire.Admissibility

namespace FvapiProof.Wire

open Fvapi.Wire

-- Each route discharges the schema/query/body-mode obligations independently.
theorem health_admissible : FvapiSpec.Wire.tableAdmissible .health = true := by decide
theorem me_admissible : FvapiSpec.Wire.tableAdmissible .me = true := by decide
theorem catalog_admissible : FvapiSpec.Wire.tableAdmissible .catalog = true := by decide
theorem entry_admissible : FvapiSpec.Wire.tableAdmissible .entry = true := by decide
theorem lookup_admissible : FvapiSpec.Wire.tableAdmissible .lookup = true := by decide
theorem matches_admissible : FvapiSpec.Wire.tableAdmissible .matches = true := by decide
theorem bundle_admissible : FvapiSpec.Wire.tableAdmissible .bundle = true := by decide
theorem check_admissible : FvapiSpec.Wire.tableAdmissible .check = true := by decide
theorem request_admissible : FvapiSpec.Wire.tableAdmissible .request = true := by decide
theorem rows_admissible : FvapiSpec.Wire.tableAdmissible .rows = true := by decide
theorem changes_admissible : FvapiSpec.Wire.tableAdmissible .changes = true := by decide
theorem row_admissible : FvapiSpec.Wire.tableAdmissible .row = true := by decide
theorem claim_admissible : FvapiSpec.Wire.tableAdmissible .claim = true := by decide
theorem release_admissible : FvapiSpec.Wire.tableAdmissible .release = true := by decide
theorem decline_admissible : FvapiSpec.Wire.tableAdmissible .decline = true := by decide
theorem resolve_admissible : FvapiSpec.Wire.tableAdmissible .resolve = true := by decide
theorem answers_admissible : FvapiSpec.Wire.tableAdmissible .answers = true := by decide
theorem admit_admissible : FvapiSpec.Wire.tableAdmissible .admit = true := by decide

theorem all_tables_admissible (route : Route) : FvapiSpec.Wire.tableAdmissible route = true := by
  cases route
  · exact health_admissible
  · exact me_admissible
  · exact catalog_admissible
  · exact entry_admissible
  · exact lookup_admissible
  · exact matches_admissible
  · exact bundle_admissible
  · exact check_admissible
  · exact request_admissible
  · exact rows_admissible
  · exact changes_admissible
  · exact row_admissible
  · exact claim_admissible
  · exact release_admissible
  · exact decline_admissible
  · exact resolve_admissible
  · exact answers_admissible
  · exact admit_admissible

theorem json_response_record (route : Route) (status : Nat) (table : ResponseTable)
    (ht : FvapiSpec.Wire.responseTable route status = some table) (hm : table.mode = .json) :
    FvapiSpec.Wire.isRecord table.schema = true := by
  have h := all_tables_admissible route
  simp only [FvapiSpec.Wire.tableAdmissible, Bool.and_eq_true] at h
  have hall := h.2
  have hmem : table ∈ (FvapiSpec.Wire.reviewedTable route).responses :=
    List.mem_of_find?_eq_some ht
  have htable := List.all_eq_true.mp hall table hmem
  simp only [Bool.and_eq_true] at htable
  have kinds := htable.2
  rw [ite_eq_left hm] at kinds
  exact kinds

theorem json_request_record (route : Route)
    (hm : (FvapiSpec.Wire.reviewedTable route).requestMode = .json) :
    FvapiSpec.Wire.isRecord (FvapiSpec.Wire.reviewedTable route).requestSchema = true := by
  have h := all_tables_admissible route
  simp only [FvapiSpec.Wire.tableAdmissible, Bool.and_eq_true] at h
  have kinds := h.1.2
  rw [hm] at kinds
  exact kinds

end FvapiProof.Wire
