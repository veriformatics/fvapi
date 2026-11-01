import FvapiProof.Json.Decode.Parse

namespace FvapiProof.Json

open Fvapi.Json

namespace S
open FvapiSpec.Json

theorem intLit_head {cs rest : Bytes} {n : Int} (h : IntLit cs n rest) :
    ∃ d, cs.head? = some d ∧ 0x2D ≤ d ∧ d ≤ 0x39 := by
  cases h with
  | zero => exact ⟨0x30, rfl, by decide, by decide⟩
  | pos hl hh _ _ => exact ⟨_, rfl, Std.le_trans (by decide) hl, hh⟩
  | neg => exact ⟨0x2D, rfl, by decide, by decide⟩

theorem valueP_ne_nil {cs rest : Bytes} {v : Value} (h : ValueP cs v rest) : cs ≠ [] := by
  cases h with
  | int hi => cases hi <;> simp
  | str hs => cases hs <;> simp
  | _ => simp

theorem valueP_head_not_closer {cs rest : Bytes} {v : Value} (h : ValueP cs v rest) :
    cs.head? ≠ some 0x5D ∧ cs.head? ≠ some 0x7D := by
  cases h with
  | int hi =>
    rcases intLit_head hi with ⟨d, hd, _, hh⟩
    rw [hd]
    constructor <;> intro he <;> have he' := Option.some.inj he <;> subst d <;> simp at hh
  | str hs => cases hs <;> simp
  | _ => simp

theorem elems_head_not_closer {cs rest : Bytes} {xs : List Value} (h : Elems cs xs rest) :
    cs.head? ≠ some 0x5D := by
  cases h with
  | last hv _ => exact (valueP_head_not_closer hv).1
  | cons hv _ _ _ => exact (valueP_head_not_closer hv).1

theorem members_head_quote {cs rest : Bytes} {ms : List (String × Value)}
    (h : Members cs ms rest) : cs.head? = some 0x22 := by
  cases h with
  | last hk _ _ _ _ => cases hk; rfl
  | cons hk _ _ _ _ _ _ => cases hk; rfl
end S

theorem valueP_index_lt {b : ByteArray} {i : Nat} {v : Value} {rest : List UInt8}
    (h : FvapiSpec.Json.ValueP (bytesAt b i) v rest) : i < b.size := by
  by_cases hi : i < b.size
  · exact hi
  · exact False.elim (S.valueP_ne_nil h (bytesAt_nil (by omega)))

theorem parseValue_int {b : ByteArray} {fuel i : Nat} {d : UInt8}
    (hb : b[i]? = some d) (hl : 0x2D ≤ d) (hh : d ≤ 0x39) :
    parseValue b (fuel + 1) i = (parseInt b i).map (fun (n, j) => (Value.int n, j)) := by
  rw [parseValue]
  split <;> simp_all
  all_goals subst d <;> simp_all

mutual
/-- A value step and a sibling-loop step can share an index: their bounds differ by one. -/
theorem parseValue_complete {b : ByteArray} {fuel i : Nat} {v : Value} {rest : List UInt8}
    (h : FvapiSpec.Json.ValueP (bytesAt b i) v rest)
    (hf : 2 * (b.size - i) + 1 ≤ fuel) :
    ∃ j, parseValue b fuel i = some (v, j) ∧ bytesAt b j = rest := by
  have hi := valueP_index_lt h
  cases fuel with
  | zero => omega
  | succ fuel =>
    generalize hcs : bytesAt b i = cs at h
    cases h with
    | nullLit =>
      have h0 := (bytesAt_cons_iff b i 0x6E _).mp hcs
      have hl := literal_complete (lit := [0x75, 0x6C, 0x6C]) h0.2
      simp only [List.length_cons, List.length_nil, Nat.reduceAdd, Nat.add_assoc] at hl
      refine ⟨i + 4, ?_, hl.2⟩
      rw [parseValue]
      simp [h0.1, hl.1]
    | trueLit =>
      have h0 := (bytesAt_cons_iff b i 0x74 _).mp hcs
      have hl := literal_complete (lit := [0x72, 0x75, 0x65]) h0.2
      simp only [List.length_cons, List.length_nil, Nat.reduceAdd, Nat.add_assoc] at hl
      refine ⟨i + 4, ?_, hl.2⟩
      rw [parseValue]
      simp [h0.1, hl.1]
    | falseLit =>
      have h0 := (bytesAt_cons_iff b i 0x66 _).mp hcs
      have hl := literal_complete (lit := [0x61, 0x6C, 0x73, 0x65]) h0.2
      simp only [List.length_cons, List.length_nil, Nat.reduceAdd, Nat.add_assoc] at hl
      refine ⟨i + 5, ?_, hl.2⟩
      rw [parseValue]
      simp [h0.1, hl.1]
    | int hn =>
      rw [← hcs] at hn
      rcases parseInt_complete hn with ⟨j, hp, hr⟩
      rcases S.intLit_head hn with ⟨d, hd, hlo, hhi⟩
      rw [bytesAt_head] at hd
      exact ⟨j, by rw [parseValue_int hd hlo hhi, hp]; rfl, hr⟩
    | str hs =>
      rw [← hcs] at hs
      rcases strLit_complete hs with ⟨hq, j, hp, hr⟩
      refine ⟨j, ?_, hr⟩
      rw [parseValue]
      simp [hq, hp]
    | arrEmpty hw =>
      have h0 := (bytesAt_cons_iff b i 0x5B _).mp hcs
      rw [← h0.2] at hw
      have hs := skipWs_complete hw
      have hc := (bytesAt_cons_iff b (skipWs b (i + 1)) 0x5D _).mp hs
      refine ⟨skipWs b (i + 1) + 1, ?_, hc.2⟩
      rw [parseValue]
      simp [h0.1, hc.1]
    | arr hw he =>
      have h0 := (bytesAt_cons_iff b i 0x5B _).mp hcs
      rw [← h0.2] at hw
      have hs := skipWs_complete hw
      rw [← hs] at he
      have hg := skipWs_ge b (i + 1)
      have hf' : 2 * (b.size - skipWs b (i + 1)) + 2 ≤ fuel := by omega
      rcases parseElems_complete he #[] hf' with ⟨j, hp, hr⟩
      have hnc := S.elems_head_not_closer he
      rw [bytesAt_head] at hnc
      refine ⟨j, ?_, hr⟩
      rw [parseValue]
      simpa [h0.1, hnc] using hp
    | objEmpty hw =>
      have h0 := (bytesAt_cons_iff b i 0x7B _).mp hcs
      rw [← h0.2] at hw
      have hs := skipWs_complete hw
      have hc := (bytesAt_cons_iff b (skipWs b (i + 1)) 0x7D _).mp hs
      refine ⟨skipWs b (i + 1) + 1, ?_, hc.2⟩
      rw [parseValue]
      simp [h0.1, hc.1]
    | obj hw hm =>
      have h0 := (bytesAt_cons_iff b i 0x7B _).mp hcs
      rw [← h0.2] at hw
      have hs := skipWs_complete hw
      rw [← hs] at hm
      have hg := skipWs_ge b (i + 1)
      have hf' : 2 * (b.size - skipWs b (i + 1)) + 2 ≤ fuel := by omega
      rcases parseMembers_complete hm #[] hf' with ⟨j, hp, hr⟩
      have hnc := S.members_head_quote hm
      rw [bytesAt_head] at hnc
      refine ⟨j, ?_, hr⟩
      rw [parseValue]
      simpa [h0.1, hnc] using hp
termination_by fuel

theorem parseElems_complete {b : ByteArray} {fuel i : Nat} {xs : List Value}
    {rest : List UInt8} (h : FvapiSpec.Json.Elems (bytesAt b i) xs rest) (acc : Array Value)
    (hf : 2 * (b.size - i) + 2 ≤ fuel) :
    ∃ j, parseElems b fuel i acc = some (.arr (acc.toList ++ xs), j) ∧ bytesAt b j = rest := by
  cases fuel with
  | zero => omega
  | succ fuel =>
    generalize hcs : bytesAt b i = cs at h
    cases h with
    | last hv hw =>
      rw [← hcs] at hv
      rcases parseValue_complete hv (by omega : 2 * (b.size - i) + 1 ≤ fuel) with
        ⟨k, hp, hr⟩
      rw [← hr] at hw
      have hs := skipWs_complete hw
      have hc := (bytesAt_cons_iff b (skipWs b k) 0x5D _).mp hs
      refine ⟨skipWs b k + 1, ?_, hc.2⟩
      rw [parseElems]
      simp [hp, hc.1]
    | cons hv hw hw' he =>
      rw [← hcs] at hv
      rcases parseValue_complete hv (by omega : 2 * (b.size - i) + 1 ≤ fuel) with
        ⟨k, hp, hr⟩
      have hbound := parseValue_sound hp
      rw [← hr] at hw
      have hs := skipWs_complete hw
      have hc := (bytesAt_cons_iff b (skipWs b k) 0x2C _).mp hs
      rw [← hc.2] at hw'
      have hs' := skipWs_complete hw'
      rw [← hs'] at he
      have hg₁ := skipWs_ge b k
      have hg₂ := skipWs_ge b (skipWs b k + 1)
      have hstart := hbound.2.1
      have hf' : 2 * (b.size - skipWs b (skipWs b k + 1)) + 2 ≤ fuel := by omega
      rcases parseElems_complete he (acc.push _) hf' with ⟨j, hp', hr'⟩
      refine ⟨j, ?_, hr'⟩
      rw [parseElems]
      simpa [hp, hc.1, Array.toList_push, List.append_assoc] using hp'
termination_by fuel

theorem parseMembers_complete {b : ByteArray} {fuel i : Nat} {ms : List (String × Value)}
    {rest : List UInt8} (h : FvapiSpec.Json.Members (bytesAt b i) ms rest)
    (acc : Array (String × Value)) (hf : 2 * (b.size - i) + 2 ≤ fuel) :
    ∃ j, parseMembers b fuel i acc = some (.obj (acc.toList ++ ms), j) ∧ bytesAt b j = rest := by
  cases fuel with
  | zero => omega
  | succ fuel =>
    generalize hcs : bytesAt b i = cs at h
    cases h with
    | last hk hw₁ hw₂ hv hw₃ =>
      rw [← hcs] at hk
      rcases strLit_complete hk with ⟨hq, k, hkey, hrkey⟩
      have hkeybound := strLit_sound hq hkey
      rw [← hrkey] at hw₁
      have hs₁ := skipWs_complete hw₁
      have hcolon := (bytesAt_cons_iff b (skipWs b k) 0x3A _).mp hs₁
      rw [← hcolon.2] at hw₂
      have hs₂ := skipWs_complete hw₂
      rw [← hs₂] at hv
      have hg₁ := skipWs_ge b k
      have hg₂ := skipWs_ge b (skipWs b k + 1)
      have hstart := hkeybound.2.1
      have hf' : 2 * (b.size - skipWs b (skipWs b k + 1)) + 1 ≤ fuel := by omega
      rcases parseValue_complete hv hf' with ⟨m, hp, hr⟩
      rw [← hr] at hw₃
      have hs₃ := skipWs_complete hw₃
      have hc := (bytesAt_cons_iff b (skipWs b m) 0x7D _).mp hs₃
      refine ⟨skipWs b m + 1, ?_, hc.2⟩
      rw [parseMembers]
      simp [hq, hkey, hcolon.1, hp, hc.1]
    | cons hk hw₁ hw₂ hv hw₃ hw₄ hm =>
      rw [← hcs] at hk
      rcases strLit_complete hk with ⟨hq, k, hkey, hrkey⟩
      have hkeybound := strLit_sound hq hkey
      rw [← hrkey] at hw₁
      have hs₁ := skipWs_complete hw₁
      have hcolon := (bytesAt_cons_iff b (skipWs b k) 0x3A _).mp hs₁
      rw [← hcolon.2] at hw₂
      have hs₂ := skipWs_complete hw₂
      rw [← hs₂] at hv
      have hg₁ := skipWs_ge b k
      have hg₂ := skipWs_ge b (skipWs b k + 1)
      have hstart := hkeybound.2.1
      have hf' : 2 * (b.size - skipWs b (skipWs b k + 1)) + 1 ≤ fuel := by omega
      rcases parseValue_complete hv hf' with ⟨m, hp, hr⟩
      have hvbound := parseValue_sound hp
      rw [← hr] at hw₃
      have hs₃ := skipWs_complete hw₃
      have hc := (bytesAt_cons_iff b (skipWs b m) 0x2C _).mp hs₃
      rw [← hc.2] at hw₄
      have hs₄ := skipWs_complete hw₄
      rw [← hs₄] at hm
      have hg₃ := skipWs_ge b m
      have hg₄ := skipWs_ge b (skipWs b m + 1)
      have hmid := hvbound.2.1
      have hfm : 2 * (b.size - skipWs b (skipWs b m + 1)) + 2 ≤ fuel := by omega
      rcases parseMembers_complete hm (acc.push _) hfm with ⟨j, hp', hr'⟩
      refine ⟨j, ?_, hr'⟩
      rw [parseMembers]
      simpa [hq, hkey, hcolon.1, hp, hc.1, Array.toList_push, List.append_assoc] using hp'
termination_by fuel
end

end FvapiProof.Json
