import FvapiProof.Json.Decode.Int

namespace FvapiProof.Json

open Fvapi.Json

mutual
theorem parseValue_sound {b : ByteArray} {fuel i j : Nat} {v : Value}
    (h : parseValue b fuel i = some (v, j)) :
    FvapiSpec.Json.ValueP (bytesAt b i) v (bytesAt b j) ∧ i < j ∧ j ≤ b.size := by
  cases fuel with
  | zero => simp [parseValue] at h
  | succ fuel =>
    rw [parseValue] at h
    split at h
    · rename_i hb
      rcases Option.map_eq_some_iff.mp h with ⟨k, hp, he⟩
      rcases Prod.mk.inj he with ⟨rfl, rfl⟩
      have hi := index_lt_of_some hb
      have hs := literal_sound hp
      refine ⟨?_, ?_, literal_le (by omega) hp⟩
      · rw [bytesAt_of_some hb, hs.1]
        exact .nullLit
      · have hk := hs.2
        simp only [List.length_cons, List.length_nil] at hk
        omega
    · rename_i hb
      rcases Option.map_eq_some_iff.mp h with ⟨k, hp, he⟩
      rcases Prod.mk.inj he with ⟨rfl, rfl⟩
      have hi := index_lt_of_some hb
      have hs := literal_sound hp
      refine ⟨?_, ?_, literal_le (by omega) hp⟩
      · rw [bytesAt_of_some hb, hs.1]
        exact .trueLit
      · have hk := hs.2
        simp only [List.length_cons, List.length_nil] at hk
        omega
    · rename_i hb
      rcases Option.map_eq_some_iff.mp h with ⟨k, hp, he⟩
      rcases Prod.mk.inj he with ⟨rfl, rfl⟩
      have hi := index_lt_of_some hb
      have hs := literal_sound hp
      refine ⟨?_, ?_, literal_le (by omega) hp⟩
      · rw [bytesAt_of_some hb, hs.1]
        exact .falseLit
      · have hk := hs.2
        simp only [List.length_cons, List.length_nil] at hk
        omega
    · rename_i hb
      rcases Option.map_eq_some_iff.mp h with ⟨⟨s, k⟩, hp, he⟩
      rcases Prod.mk.inj he with ⟨rfl, rfl⟩
      have hs := strLit_sound hb hp
      exact ⟨.str hs.1, hs.2⟩
    · rename_i hb
      dsimp only at h
      split at h
      · rename_i hc
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        rcases h with ⟨rfl, rfl⟩
        have hc := beq_iff_eq.mp hc
        have hi := index_lt_of_some hc
        have hw := skipWs_sound b (i + 1)
        rw [bytesAt_of_some hc] at hw
        have hg := skipWs_ge b (i + 1)
        refine ⟨?_, by omega, by omega⟩
        rw [bytesAt_of_some hb]
        exact .arrEmpty hw
      · rcases parseElems_sound h with ⟨xs, hv, hs, hij, hj⟩
        simp only [List.nil_append] at hv
        subst v
        have hg := skipWs_ge b (i + 1)
        refine ⟨?_, by omega, hj⟩
        rw [bytesAt_of_some hb]
        exact .arr (skipWs_sound b (i + 1)) hs
    · rename_i hb
      dsimp only at h
      split at h
      · rename_i hc
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        rcases h with ⟨rfl, rfl⟩
        have hc := beq_iff_eq.mp hc
        have hi := index_lt_of_some hc
        have hw := skipWs_sound b (i + 1)
        rw [bytesAt_of_some hc] at hw
        have hg := skipWs_ge b (i + 1)
        refine ⟨?_, by omega, by omega⟩
        rw [bytesAt_of_some hb]
        exact .objEmpty hw
      · rcases parseMembers_sound h with ⟨ms, hv, hs, hij, hj⟩
        simp only [List.nil_append] at hv
        subst v
        have hg := skipWs_ge b (i + 1)
        refine ⟨?_, by omega, hj⟩
        rw [bytesAt_of_some hb]
        exact .obj (skipWs_sound b (i + 1)) hs
    · rcases Option.map_eq_some_iff.mp h with ⟨⟨n, k⟩, hp, he⟩
      rcases Prod.mk.inj he with ⟨rfl, rfl⟩
      have hs := parseInt_sound hp
      exact ⟨.int hs.1, hs.2⟩
    · contradiction
termination_by fuel

theorem parseElems_sound {b : ByteArray} {fuel i j : Nat} {acc : Array Value} {v : Value}
    (h : parseElems b fuel i acc = some (v, j)) :
    ∃ xs, v = .arr (acc.toList ++ xs) ∧
      FvapiSpec.Json.Elems (bytesAt b i) xs (bytesAt b j) ∧ i < j ∧ j ≤ b.size := by
  cases fuel with
  | zero => simp [parseElems] at h
  | succ fuel =>
    rw [parseElems] at h
    split at h
    · contradiction
    · rename_i w k hp
      have hv := parseValue_sound hp
      dsimp only at h
      split at h
      · rename_i hc
        rcases parseElems_sound h with ⟨xs, he, hs, hij, hj⟩
        have hw := skipWs_sound b k
        rw [bytesAt_of_some hc] at hw
        refine ⟨w :: xs, ?_, .cons hv.1 hw (skipWs_sound b _) hs, ?_, hj⟩
        · simpa [Array.toList_push, List.append_assoc] using he
        · have hg₁ := skipWs_ge b k
          have hg₂ := skipWs_ge b (skipWs b k + 1)
          have hstart := hv.2.1
          omega
      · rename_i hc
        simp only [Option.some.injEq, Prod.mk.injEq] at h
        rcases h with ⟨rfl, rfl⟩
        have hw := skipWs_sound b k
        rw [bytesAt_of_some hc] at hw
        refine ⟨[w], ?_, .last hv.1 hw, ?_, ?_⟩
        · simp
        · have hg := skipWs_ge b k
          have hstart := hv.2.1
          omega
        · have := index_lt_of_some hc
          omega
      · contradiction
termination_by fuel

theorem parseMembers_sound {b : ByteArray} {fuel i j : Nat}
    {acc : Array (String × Value)} {v : Value}
    (h : parseMembers b fuel i acc = some (v, j)) :
    ∃ ms, v = .obj (acc.toList ++ ms) ∧
      FvapiSpec.Json.Members (bytesAt b i) ms (bytesAt b j) ∧ i < j ∧ j ≤ b.size := by
  cases fuel with
  | zero => simp [parseMembers] at h
  | succ fuel =>
    rw [parseMembers] at h
    split at h
    · contradiction
    · rename_i hquote
      have hquote : b[i]? = some 0x22 := by simpa using hquote
      split at h
      · contradiction
      · rename_i key k hp
        have hk := strLit_sound hquote hp
        dsimp only at h
        split at h
        · contradiction
        · rename_i hcolon
          have hcolon : b[skipWs b k]? = some 0x3A := by simpa using hcolon
          split at h
          · contradiction
          · rename_i w m hvp
            have hv := parseValue_sound hvp
            have hw₁ := skipWs_sound b k
            rw [bytesAt_of_some hcolon] at hw₁
            have hw₂ := skipWs_sound b (skipWs b k + 1)
            have hw₃ := skipWs_sound b m
            split at h
            · rename_i hc
              rcases parseMembers_sound h with ⟨ms, he, hs, hij, hj⟩
              rw [bytesAt_of_some hc] at hw₃
              refine ⟨(key, w) :: ms, ?_,
                .cons hk.1 hw₁ hw₂ hv.1 hw₃ (skipWs_sound b _) hs, ?_, hj⟩
              · simpa [Array.toList_push, List.append_assoc] using he
              · have hg₁ := skipWs_ge b k
                have hg₂ := skipWs_ge b (skipWs b k + 1)
                have hg₃ := skipWs_ge b m
                have hg₄ := skipWs_ge b (skipWs b m + 1)
                have hstart := hk.2.1
                have hmid := hv.2.1
                omega
            · rename_i hc
              simp only [Option.some.injEq, Prod.mk.injEq] at h
              rcases h with ⟨rfl, rfl⟩
              rw [bytesAt_of_some hc] at hw₃
              refine ⟨[(key, w)], ?_, .last hk.1 hw₁ hw₂ hv.1 hw₃, ?_, ?_⟩
              · simp
              · have hg₁ := skipWs_ge b k
                have hg₂ := skipWs_ge b (skipWs b k + 1)
                have hg₃ := skipWs_ge b m
                have hstart := hk.2.1
                have hmid := hv.2.1
                omega
              · have := index_lt_of_some hc
                omega
            · contradiction
termination_by fuel
end

#print axioms parseValue_sound

end FvapiProof.Json
