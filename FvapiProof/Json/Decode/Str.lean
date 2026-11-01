import FvapiProof.Json.Decode.Index
import FvapiProof.Json.Decode.Utf8

namespace FvapiProof.Json

open Fvapi.Json

namespace S
open FvapiSpec.Json

theorem ws_unique {cs r s : Bytes} (h : Ws cs r) (h' : Ws cs s) : r = s := by
  induction h generalizing s with
  | stop hs =>
    cases h' with
    | stop => rfl
    | @skip b _ _ hb _ => have hn := hs b (by simp); simp_all
  | @skip b _ _ hb _ ih =>
    cases h' with
    | stop hs => have hn := hs b (by simp); simp_all
    | skip _ ht => exact ih ht
end S

theorem skipWs_sound (b : ByteArray) (i : Nat) :
    FvapiSpec.Json.Ws (bytesAt b i) (bytesAt b (skipWs b i)) := by
  rw [skipWs]
  by_cases hi : i < b.size
  · simp only [hi, dite_true]
    by_cases hw : isWs b[i] = true
    · simp only [hw, ite_true]
      rw [bytesAt_cons hi]
      exact .skip hw (skipWs_sound b (i + 1))
    · simp only [hw]
      apply FvapiSpec.Json.Ws.stop
      rw [bytesAt_cons hi]
      change ∀ c ∈ some b[i], isWs c = false
      simpa using hw
  · simp only [hi, dite_false]
    apply FvapiSpec.Json.Ws.stop
    rw [bytesAt_nil (by omega : b.size ≤ i)]
    simp
termination_by b.size - i

theorem skipWs_complete {b : ByteArray} {i : Nat} {rest : List UInt8}
    (h : FvapiSpec.Json.Ws (bytesAt b i) rest) : bytesAt b (skipWs b i) = rest :=
  S.ws_unique (skipWs_sound b i) h

theorem skipWs_ge (b : ByteArray) (i : Nat) : i ≤ skipWs b i := by
  rw [skipWs]
  split
  · split
    · have := skipWs_ge b (i + 1)
      omega
    · omega
  · omega
termination_by b.size - i

theorem skipWs_le {b : ByteArray} {i : Nat} (hi : i ≤ b.size) : skipWs b i ≤ b.size := by
  rw [skipWs]
  split
  · split
    · exact skipWs_le (by omega)
    · exact hi
  · exact hi
termination_by b.size - i

theorem literal_sound {b : ByteArray} {i j : Nat} {lit : List UInt8}
    (h : literal b i lit = some j) :
    bytesAt b i = lit ++ bytesAt b j ∧ j = i + lit.length := by
  induction lit generalizing i with
  | nil =>
    simp only [literal, Option.some.injEq] at h
    subst j
    exact ⟨rfl, rfl⟩
  | cons c cs ih =>
    rw [literal] at h
    split at h
    · rename_i hc
      have hc : b[i]? = some c := beq_iff_eq.mp hc
      rcases ih h with ⟨hs, hj⟩
      rw [bytesAt_of_some hc, hs]
      exact ⟨rfl, by simp only [List.length_cons]; omega⟩
    · contradiction

theorem literal_le {b : ByteArray} {i j : Nat} {lit : List UInt8} (hi : i ≤ b.size)
    (h : literal b i lit = some j) : j ≤ b.size := by
  have hs := literal_sound h
  have hl := congrArg List.length hs.1
  simp only [bytesAt_length, List.length_append] at hl
  have hj := hs.2
  omega

theorem literal_complete {b : ByteArray} {i : Nat} {lit rest : List UInt8}
    (h : bytesAt b i = lit ++ rest) :
    literal b i lit = some (i + lit.length) ∧ bytesAt b (i + lit.length) = rest := by
  induction lit generalizing i with
  | nil => simpa [literal] using h
  | cons c cs ih =>
    have hc := (bytesAt_cons_iff b i c _).mp h
    rcases ih hc.2 with ⟨hl, hr⟩
    constructor
    · simp only [literal, hc.1, BEq.rfl, ite_true]
      simpa only [List.length_cons, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using hl
    · simpa only [List.length_cons, Nat.add_assoc, Nat.add_comm, Nat.add_left_comm] using hr

theorem hex4_sound {b : ByteArray} {i n : Nat} (h : hex4 b i = some n) :
    FvapiSpec.Json.Hex4 (bytesAt b i) n (bytesAt b (i + 4)) := by
  simp only [hex4, Option.bind_eq_bind, Option.bind_eq_some_iff] at h
  rcases h with ⟨a, ha, va, hva, c, hc, vc, hvc, d, hd, vd, hvd, e, he, ve, hve, hn⟩
  have hn : ((va * 16 + vc) * 16 + vd) * 16 + ve = n := Option.some.inj hn
  subst n
  rw [bytesAt_of_some ha, bytesAt_of_some hc]
  simp only [Nat.add_assoc, Nat.reduceAdd]
  rw [bytesAt_of_some hd]
  simp only [Nat.add_assoc, Nat.reduceAdd]
  rw [bytesAt_of_some he]
  simp only [Nat.add_assoc, Nat.reduceAdd]
  exact .mk hva hvc hvd hve

theorem hex4_complete {b : ByteArray} {i n : Nat} {rest : List UInt8}
    (h : FvapiSpec.Json.Hex4 (bytesAt b i) n rest) :
    hex4 b i = some n ∧ bytesAt b (i + 4) = rest := by
  generalize hcs : bytesAt b i = cs at h
  cases h with
  | @mk a c d e rest va vc vd ve ha hc hd he =>
    have h0 := (bytesAt_cons_iff b i a _).mp hcs
    have h1 := (bytesAt_cons_iff b (i + 1) c _).mp h0.2
    simp only [Nat.add_assoc, Nat.reduceAdd] at h1
    have h2 := (bytesAt_cons_iff b (i + 2) d _).mp h1.2
    simp only [Nat.add_assoc, Nat.reduceAdd] at h2
    have h3 := (bytesAt_cons_iff b (i + 3) e _).mp h2.2
    simp only [Nat.add_assoc, Nat.reduceAdd] at h3
    refine ⟨?_, h3.2⟩
    change hexVal a = some va at ha
    change hexVal c = some vc at hc
    change hexVal d = some vd at hd
    change hexVal e = some ve at he
    simp [hex4, h0.1, h1.1, h2.1, h3.1, ha, hc, hd, he]

theorem hex4_length {cs rest : List UInt8} {n : Nat}
    (h : FvapiSpec.Json.Hex4 cs n rest) : cs.length = rest.length + 4 := by
  cases h
  simp

theorem hex4_le {b : ByteArray} {i n : Nat} (h : hex4 b i = some n) : i + 4 ≤ b.size := by
  have hl := hex4_length (hex4_sound h)
  rw [bytesAt_length, bytesAt_length] at hl
  omega

theorem unicodeEscape_sound {b : ByteArray} {i j : Nat} {c : Char}
    (h : unicodeEscape b i = some (c, j)) :
    FvapiSpec.Json.Escape (0x75 :: bytesAt b i) c (bytesAt b j) ∧ j ≤ b.size := by
  cases hh : hex4 b i with
  | none => simp [unicodeEscape, hh] at h
  | some n =>
    by_cases hn : n < 0xD800 ∨ 0xDFFF < n
    · simp only [unicodeEscape, hh, hn, ite_true, Option.some.injEq, Prod.mk.injEq] at h
      rcases h with ⟨rfl, rfl⟩
      exact ⟨.unit (hex4_sound hh) hn, hex4_le hh⟩
    · by_cases hhigh : 0xDBFF < n
      · simp [unicodeEscape, hh, hn, hhigh] at h
      · by_cases hp : b[i + 4]? = some 0x5C ∧ b[i + 5]? = some 0x75
        · cases hl : hex4 b (i + 6) with
          | none => simp [unicodeEscape, hh, hn, hhigh, hp, hl] at h
          | some lo =>
            by_cases hlo : 0xDC00 ≤ lo ∧ lo ≤ 0xDFFF
            · simp [unicodeEscape, hh, hn, hhigh, hp, hl, hlo] at h
              rcases h with ⟨rfl, rfl⟩
              have hhi := hex4_sound hh
              rw [bytesAt_of_some hp.1] at hhi
              simp only [Nat.add_assoc, Nat.reduceAdd] at hhi
              rw [bytesAt_of_some hp.2] at hhi
              simp only [Nat.add_assoc, Nat.reduceAdd] at hhi
              refine ⟨.pair hhi (hex4_sound hl) (by omega) (by omega) hlo.1 hlo.2, ?_⟩
              have := hex4_le hl
              omega
            · simp [unicodeEscape, hh, hn, hhigh, hp, hl, hlo] at h
        · simp [unicodeEscape, hh, hn, hhigh, hp] at h

theorem unicodeEscape_unit_complete {b : ByteArray} {i n : Nat} {rest : List UInt8}
    (hh : FvapiSpec.Json.Hex4 (bytesAt b i) n rest) (hn : n < 0xD800 ∨ 0xDFFF < n) :
    unicodeEscape b i = some (Char.ofNat n, i + 4) ∧ bytesAt b (i + 4) = rest := by
  have hh := hex4_complete hh
  exact ⟨by simp [unicodeEscape, hh.1, hn], hh.2⟩

theorem unicodeEscape_pair_complete {b : ByteArray} {i hi lo : Nat}
    {cs rest : List UInt8} (hh : FvapiSpec.Json.Hex4 (bytesAt b i) hi (0x5C :: 0x75 :: cs))
    (hl : FvapiSpec.Json.Hex4 cs lo rest) (hhi₁ : 0xD800 ≤ hi) (hhi₂ : hi ≤ 0xDBFF)
    (hlo₁ : 0xDC00 ≤ lo) (hlo₂ : lo ≤ 0xDFFF) :
    unicodeEscape b i =
        some (Char.ofNat (0x10000 + (hi - 0xD800) * 0x400 + (lo - 0xDC00)), i + 10) ∧
      bytesAt b (i + 10) = rest := by
  have hh := hex4_complete hh
  have h4 := (bytesAt_cons_iff b (i + 4) 0x5C _).mp hh.2
  simp only [Nat.add_assoc, Nat.reduceAdd] at h4
  have h5 := (bytesAt_cons_iff b (i + 5) 0x75 _).mp h4.2
  simp only [Nat.add_assoc, Nat.reduceAdd] at h5
  rw [← h5.2] at hl
  have hl := hex4_complete hl
  simp only [Nat.add_assoc, Nat.reduceAdd] at hl
  have hnot : ¬(hi < 0xD800 ∨ 0xDFFF < hi) := by omega
  have hnot' : ¬0xDBFF < hi := by omega
  refine ⟨?_, hl.2⟩
  simp [unicodeEscape, hh.1, hnot, hnot', h4.1, h5.1, hl.1, hlo₁, hlo₂]

theorem escape_sound {b : ByteArray} {i j : Nat} {c : Char}
    (h : escape b i = some (c, j)) :
    FvapiSpec.Json.Escape (bytesAt b i) c (bytesAt b j) ∧ j ≤ b.size := by
  unfold escape at h
  split at h
  all_goals first
    | contradiction
    | (have hu := unicodeEscape_sound h
       rename_i hb
       refine ⟨?_, hu.2⟩
       rw [bytesAt_of_some hb]
       exact hu.1)
    | (simp only [Option.some.injEq, Prod.mk.injEq] at h
       rcases h with ⟨rfl, rfl⟩
       rename_i hb
       refine ⟨?_, by have := index_lt_of_some hb; omega⟩
       rw [bytesAt_of_some hb]
       constructor)

theorem escape_complete {b : ByteArray} {i : Nat} {c : Char} {rest : List UInt8}
    (h : FvapiSpec.Json.Escape (bytesAt b i) c rest) :
    ∃ j, escape b i = some (c, j) ∧ bytesAt b j = rest := by
  generalize hcs : bytesAt b i = cs at h
  cases h with
  | unit hh hn =>
    have h0 := (bytesAt_cons_iff b i 0x75 _).mp hcs
    rw [← h0.2] at hh
    have hu := unicodeEscape_unit_complete hh hn
    exact ⟨i + 1 + 4, by simp [escape, h0.1, hu.1], hu.2⟩
  | pair hh hl hhi₁ hhi₂ hlo₁ hlo₂ =>
    have h0 := (bytesAt_cons_iff b i 0x75 _).mp hcs
    rw [← h0.2] at hh
    have hu := unicodeEscape_pair_complete hh hl hhi₁ hhi₂ hlo₁ hlo₂
    exact ⟨i + 1 + 10, by simp [escape, h0.1, hu.1], hu.2⟩
  | _ =>
    have h0 := (bytesAt_cons_iff b i _ _).mp hcs
    exact ⟨i + 1, by simp [escape, h0.1], h0.2⟩

theorem push_append_ofList (acc : String) (c : Char) (cs : List Char) :
    acc.push c ++ String.ofList cs = acc ++ String.ofList (c :: cs) := by
  apply String.toList_inj.mp
  simp [List.append_assoc]

theorem parseStr_sound {b : ByteArray} {i j : Nat} {acc s : String}
    (h : parseStr b i acc = some (s, j)) :
    ∃ chs, FvapiSpec.Json.StrBody (bytesAt b i) chs (bytesAt b j) ∧
      s = acc ++ String.ofList chs ∧ i < j ∧ j ≤ b.size := by
  rw [parseStr] at h
  by_cases hi : i < b.size
  · simp only [hi, dite_true] at h
    by_cases hq : b[i] == 0x22
    · simp only [hq, ite_true, Option.some.injEq, Prod.mk.injEq] at h
      rcases h with ⟨rfl, rfl⟩
      have hq : b[i]? = some 0x22 := by simpa [hi] using beq_iff_eq.mp hq
      refine ⟨[], ?_, by simp, by omega, by omega⟩
      rw [bytesAt_of_some hq]
      exact .close
    · by_cases hb : b[i] == 0x5C
      · simp [hq, hb] at h
        split at h
        · rename_i c k he
          have hstep := escape_lt he
          rcases parseStr_sound h with ⟨cs, hs, ha, hij, hj⟩
          have hb : b[i]? = some 0x5C := by simpa [hi] using beq_iff_eq.mp hb
          refine ⟨c :: cs, ?_, ?_, ?_, hj⟩
          · rw [bytesAt_of_some hb]
            exact .esc (escape_sound he).1 hs
          · exact ha.trans (push_append_ofList acc c cs)
          · have := escape_lt he
            omega
        · contradiction
      · simp [hq, hb] at h
        rcases h with ⟨hge, h⟩
        split at h
        · rename_i c hd
          have hstep := c.utf8Size_pos
          rcases parseStr_sound h with ⟨cs, hs, ha, hij, hj⟩
          have hm := utf8DecodeChar_first_mem hd
          have hc := (utf8EncodeChar_control_iff hm).mpr hge
          have hcq : c ≠ '"' := by
            intro he
            subst c
            change b[i] ∈ [0x22] at hm
            have hh : b[i] = 0x22 := by simpa using hm
            exact hq (beq_iff_eq.mpr hh)
          have hcb : c ≠ '\\' := by
            intro he
            subst c
            change b[i] ∈ [0x5C] at hm
            have hh : b[i] = 0x5C := by simpa using hm
            exact hb (beq_iff_eq.mpr hh)
          refine ⟨c :: cs, ?_, ha.trans (push_append_ofList acc c cs), ?_, hj⟩
          · rw [utf8DecodeChar_bytesAt hd]
            exact .raw hc hcq hcb hs
          · have := c.utf8Size_pos
            omega
        · contradiction
  · simp [hi] at h
termination_by b.size - i

theorem parseStr_complete {b : ByteArray} {i : Nat} {rest : List UInt8} {chs : List Char}
    (h : FvapiSpec.Json.StrBody (bytesAt b i) chs rest) (acc : String) :
    ∃ j, parseStr b i acc = some (acc ++ String.ofList chs, j) ∧ bytesAt b j = rest := by
  generalize hcs : bytesAt b i = cs at h
  cases h with
  | close =>
    have h0 := (bytesAt_cons_iff b i 0x22 _).mp hcs
    have hi := index_lt_of_some h0.1
    have hb : b[i] = 0x22 := by simpa [hi] using h0.1
    refine ⟨i + 1, ?_, h0.2⟩
    rw [parseStr]
    simp [hi, hb]
  | @raw c cs rest chs hc hq hb ht =>
    have hs : bytesAt b (i + c.utf8Size) = cs := by
      simpa only [String.length_utf8EncodeChar] using bytesAt_prefix hcs
    rw [← hs] at ht
    have hd : b.utf8DecodeChar? i = some c :=
      utf8DecodeChar_iff.mpr (by rw [hs]; exact hcs)
    have hi : i < b.size := ByteArray.lt_size_of_isSome_utf8DecodeChar? (by simp [hd])
    have hm := utf8DecodeChar_first_mem hd
    have hsafe := utf8EncodeChar_safe hq hb _ hm
    have hge := (utf8EncodeChar_control_iff hm).mp hc
    have hn : ¬b[i] < 0x20 := by
      change 32 ≤ b[i].toNat at hge
      change ¬b[i].toNat < 32
      omega
    have hstep := c.utf8Size_pos
    rcases parseStr_complete ht (acc.push c) with ⟨j, hp, hr⟩
    refine ⟨j, ?_, hr⟩
    rw [parseStr]
    simp only [hi, dite_true, beq_eq_false_iff_ne.mpr hsafe.1,
      beq_eq_false_iff_ne.mpr hsafe.2, Bool.false_eq_true, ite_false, hn]
    split
    · rename_i c' hd'
      have hec : c' = c := Option.some.inj (hd'.symm.trans hd)
      subst c'
      rw [hp, push_append_ofList]
    · rename_i hn'
      simp [hd] at hn'
  | @esc c cs cs' rest chs he ht =>
    have h0 := (bytesAt_cons_iff b i 0x5C _).mp hcs
    have hi := index_lt_of_some h0.1
    have hb : b[i] = 0x5C := by simpa [hi] using h0.1
    rw [← h0.2] at he
    rcases escape_complete he with ⟨k, hk, hr⟩
    rw [← hr] at ht
    have hstep := escape_lt hk
    rcases parseStr_complete ht (acc.push c) with ⟨j, hp, hj⟩
    refine ⟨j, ?_, hj⟩
    rw [parseStr]
    simp only [hi, dite_true, hb, show ¬((0x5C : UInt8) == 0x22) = true by decide,
      Bool.false_eq_true, ite_false, BEq.rfl, ite_true]
    split
    · rename_i c' k' he'
      have hec : (c', k') = (c, k) := Option.some.inj (he'.symm.trans hk)
      rcases Prod.mk.inj hec with ⟨rfl, rfl⟩
      rw [hp, push_append_ofList]
    · rename_i hn'
      simp [hk] at hn'
termination_by b.size - i

theorem strLit_sound {b : ByteArray} {i j : Nat} {s : String}
    (hq : b[i]? = some 0x22) (h : parseStr b (i + 1) "" = some (s, j)) :
    FvapiSpec.Json.StrLit (bytesAt b i) s (bytesAt b j) ∧ i < j ∧ j ≤ b.size := by
  rcases parseStr_sound h with ⟨cs, hs, ha, hij, hj⟩
  simp only [String.empty_append] at ha
  subst s
  refine ⟨?_, by omega, hj⟩
  rw [bytesAt_of_some hq]
  exact .mk hs

theorem strLit_complete {b : ByteArray} {i : Nat} {s : String} {rest : List UInt8}
    (h : FvapiSpec.Json.StrLit (bytesAt b i) s rest) :
    b[i]? = some 0x22 ∧ ∃ j, parseStr b (i + 1) "" = some (s, j) ∧ bytesAt b j = rest := by
  generalize hcs : bytesAt b i = cs at h
  cases h with
  | mk hb =>
    have h0 := (bytesAt_cons_iff b i 0x22 _).mp hcs
    rw [← h0.2] at hb
    have hp := parseStr_complete hb ""
    simpa only [String.empty_append] using And.intro h0.1 hp

#print axioms parseStr_sound
#print axioms parseStr_complete

end FvapiProof.Json
