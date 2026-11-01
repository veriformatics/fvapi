import FvapiProof.Json.Decode
import FvapiProof.Json.Print

namespace FvapiProof.Json

open Fvapi.Json FvapiSpec.Json

/-- Shipped print, then shipped decode: `decode_exact` + `print_exact` + `round_trip`. -/
theorem print_decode : FvapiSelf.Json.PrintDecode := by
  intro v hv
  rw [decode_exact, print_exact]
  exact round_trip v hv

/-- Two valid values with one canonical text: both are the decoder's single answer on it. -/
theorem canonical_injective : FvapiSelf.Json.CanonicalInjective := by
  intro v w hv hw h
  have hw' := round_trip w hw
  rw [← h] at hw'
  let b : ByteArray := ⟨(canonical v).toArray⟩
  have hb : b.data.toList = canonical v := by simp [b]
  have h1 : decode b = .ok v := (decode_exact b (.ok v)).mpr (hb ▸ round_trip v hv)
  have h2 : decode b = .ok w := (decode_exact b (.ok w)).mpr (hb ▸ hw')
  exact Except.ok.inj (h1.symm.trans h2)

end FvapiProof.Json
