import FvapiProof.Json.Print.Builder
import FvapiProof.Json.Print.Grammar
import FvapiProof.Json.Print.Depth
import FvapiProof.Json.Print.Normalize

namespace FvapiProof.Json

theorem print_exact : FvapiSelf.Json.PrintExact := by
  intro v
  simpa [Fvapi.Json.print] using printTo_exact ByteArray.empty v

theorem round_trip : FvapiSelf.Json.RoundTrip := by
  intro v hv
  obtain ⟨hi, hs, hd, hk⟩ := hv
  have hn := canonical_invariants v hk
  have ho := FvapiSpec.Json.Outcome.ok
    (by rw [lexicalDepth_canonical]; exact hd) (canonical_text v hi) hs hn.2
  simpa only [hn.1] using ho

end FvapiProof.Json

#print axioms FvapiProof.Json.print_exact
#print axioms FvapiProof.Json.round_trip
