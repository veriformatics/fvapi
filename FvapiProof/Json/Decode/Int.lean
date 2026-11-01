import FvapiProof.Json.Decode.Str

namespace FvapiProof.Json

open Fvapi.Json

/-- The digit loop admits a zero-length run; IntLit enters it at a nonzero digit. -/
inductive DigitTail : Nat → List UInt8 → Nat → List UInt8 → Prop
  | stop {acc : Nat} {rest : List UInt8} :
      (∀ b ∈ rest.head?, FvapiSpec.Json.isDigit b = false) → DigitTail acc rest acc rest
  | step {acc n : Nat} {d : UInt8} {cs rest : List UInt8} :
      FvapiSpec.Json.isDigit d = true →
      DigitTail (10 * acc + (d - 0x30).toNat) cs n rest → DigitTail acc (d :: cs) n rest

theorem digitTail_ge {acc n : Nat} {cs rest : List UInt8} (h : DigitTail acc cs n rest) :
    acc ≤ n := by
  induction h with
  | stop => omega
  | step _ _ ih => omega

theorem digitTail_run {acc n : Nat} {d : UInt8} {cs rest : List UInt8}
    (hd : FvapiSpec.Json.isDigit d = true)
    (h : DigitTail (10 * acc + (d - 0x30).toNat) cs n rest) :
    FvapiSpec.Json.DigitRun acc (d :: cs) n rest := by
  cases h with
  | stop hs => exact .last hd hs
  | step he ht => exact .more hd (digitTail_run he ht)
termination_by cs.length

theorem digitRun_tail {acc n : Nat} {cs rest : List UInt8}
    (h : FvapiSpec.Json.DigitRun acc cs n rest) : DigitTail acc cs n rest := by
  induction h with
  | last hd hs => exact .step hd (.stop hs)
  | more hd _ ih => exact .step hd ih

theorem digits_sound {b : ByteArray} {i j acc n : Nat} (hi : i ≤ b.size) (ha : acc ≤ maxInt)
    (h : digits b i acc = some (n, j)) :
    DigitTail acc (bytesAt b i) n (bytesAt b j) ∧ n ≤ maxInt ∧ i ≤ j ∧ j ≤ b.size := by
  rw [digits] at h
  by_cases hin : i < b.size
  · simp only [hin, dite_true] at h
    by_cases hd : 0x30 ≤ b[i] ∧ b[i] ≤ 0x39
    · simp only [hd] at h
      by_cases hn : 10 * acc + (b[i] - 0x30).toNat ≤ maxInt
      · simp only [hn, ite_true] at h
        rcases digits_sound (by omega) hn h with ⟨ht, hb, hij, hj⟩
        refine ⟨?_, hb, by omega, hj⟩
        rw [bytesAt_cons hin]
        exact .step (by simpa only [FvapiSpec.Json.isDigit, Bool.and_eq_true,
          decide_eq_true_eq] using hd) ht
      · simp [hn] at h
    · simp only [hd, ite_false, Option.some.injEq, Prod.mk.injEq] at h
      rcases h with ⟨rfl, rfl⟩
      refine ⟨.stop ?_, ha, by omega, hi⟩
      rw [bytesAt_cons hin]
      simp only [List.head?_cons, Option.mem_def, Option.some.injEq]
      intro d he
      subst d
      simpa only [Bool.eq_false_iff, ne_eq, FvapiSpec.Json.isDigit, Bool.and_eq_true,
        decide_eq_true_eq] using hd
  · simp only [hin, dite_false, Option.some.injEq, Prod.mk.injEq] at h
    rcases h with ⟨rfl, rfl⟩
    refine ⟨.stop ?_, ha, by omega, hi⟩
    rw [bytesAt_nil (by omega : b.size ≤ i)]
    simp
termination_by b.size - i

theorem digits_complete {b : ByteArray} {i acc n : Nat} {rest : List UInt8}
    (h : DigitTail acc (bytesAt b i) n rest) (hn : n ≤ maxInt) :
    ∃ j, digits b i acc = some (n, j) ∧ bytesAt b j = rest := by
  generalize hcs : bytesAt b i = cs at h
  cases h with
  | stop hs =>
    refine ⟨i, ?_, hcs⟩
    rw [digits]
    by_cases hi : i < b.size
    · simp only [hi, dite_true]
      rw [bytesAt_cons hi] at hcs
      rw [← hcs] at hs
      have hd := hs b[i] (by simp)
      have hd : ¬(0x30 ≤ b[i] ∧ b[i] ≤ 0x39) := by
        simpa only [Bool.eq_false_iff, ne_eq, FvapiSpec.Json.isDigit, Bool.and_eq_true,
          decide_eq_true_eq] using hd
      simp [hd]
    · simp [hi]
  | @step _ _ d _ _ hd ht =>
    have h0 := (bytesAt_cons_iff b i _ _).mp hcs
    have hi := index_lt_of_some h0.1
    have hb : b[i] = d := by simpa [hi] using h0.1
    have hacc := digitTail_ge ht
    rw [← h0.2] at ht
    rcases digits_complete ht hn with ⟨j, hp, hr⟩
    refine ⟨j, ?_, hr⟩
    rw [digits]
    simp only [hi, dite_true, hb]
    have hd : 0x30 ≤ d ∧ d ≤ 0x39 := by
      simpa only [FvapiSpec.Json.isDigit, Bool.and_eq_true, decide_eq_true_eq] using hd
    simp only [hd, ite_true, show 10 * acc + (d - 0x30).toNat ≤ maxInt by omega]
    exact hp
termination_by b.size - i

theorem digitRun_length_lt {acc n : Nat} {cs rest : List UInt8}
    (h : FvapiSpec.Json.DigitRun acc cs n rest) : rest.length < cs.length := by
  induction h with
  | last => simp
  | more _ _ ih => simp only [List.length_cons]; omega

theorem digitTail_nonempty {acc n : Nat} {d : UInt8} {cs rest : List UInt8}
    (h : DigitTail acc (d :: cs) n rest) (hd : FvapiSpec.Json.isDigit d = true) :
    FvapiSpec.Json.DigitRun acc (d :: cs) n rest := by
  cases h with
  | stop hs => have hnot := hs d (by simp); simp_all
  | step he ht => exact digitTail_run he ht

theorem digits_run_sound {b : ByteArray} {i j n : Nat} {d : UInt8}
    (hb : b[i]? = some d) (hd : FvapiSpec.Json.isDigit d = true)
    (h : digits b i 0 = some (n, j)) :
    FvapiSpec.Json.DigitRun 0 (bytesAt b i) n (bytesAt b j) ∧
      n ≤ maxInt ∧ i < j ∧ j ≤ b.size := by
  have hi := index_lt_of_some hb
  rcases digits_sound (by omega) (by omega) h with ⟨ht, hn, hij, hj⟩
  have hr : FvapiSpec.Json.DigitRun 0 (bytesAt b i) n (bytesAt b j) := by
    rw [bytesAt_of_some hb] at ht ⊢
    exact digitTail_nonempty ht hd
  have hl := digitRun_length_lt hr
  rw [bytesAt_length, bytesAt_length] at hl
  exact ⟨hr, hn, by omega, hj⟩

theorem parseInt_sound {b : ByteArray} {i j : Nat} {n : Int}
    (h : parseInt b i = some (n, j)) :
    FvapiSpec.Json.IntLit (bytesAt b i) n (bytesAt b j) ∧ i < j ∧ j ≤ b.size := by
  unfold parseInt at h
  split at h
  · rename_i hb
    simp only [Option.some.injEq, Prod.mk.injEq] at h
    rcases h with ⟨rfl, rfl⟩
    have hi := index_lt_of_some hb
    refine ⟨?_, by omega, by omega⟩
    rw [bytesAt_of_some hb]
    exact .zero
  · rename_i hminus
    split at h
    · rename_i d hd
      split at h
      · rename_i hnonzero
        rcases Option.map_eq_some_iff.mp h with ⟨⟨mag, k⟩, hp, he⟩
        rcases Prod.mk.inj he with ⟨rfl, rfl⟩
        have hds : FvapiSpec.Json.isDigit d = true := by
          simp only [FvapiSpec.Json.isDigit, Bool.and_eq_true, decide_eq_true_eq]
          exact ⟨Std.le_trans (by decide : (0x30 : UInt8) ≤ 0x31) hnonzero.1, hnonzero.2⟩
        rcases digits_run_sound hd hds hp with ⟨hr, hm, hij, hj⟩
        refine ⟨?_, by omega, hj⟩
        rw [bytesAt_of_some hminus, bytesAt_of_some hd]
        rw [bytesAt_of_some hd] at hr
        exact .neg hnonzero.1 hnonzero.2 hr hm
      · contradiction
    · contradiction
  · rename_i d hneq0 hneqminus hd
    split at h
    · rename_i hnonzero
      rcases Option.map_eq_some_iff.mp h with ⟨⟨mag, k⟩, hp, he⟩
      rcases Prod.mk.inj he with ⟨rfl, rfl⟩
      have hds : FvapiSpec.Json.isDigit d = true := by
        simp only [FvapiSpec.Json.isDigit, Bool.and_eq_true, decide_eq_true_eq]
        exact ⟨Std.le_trans (by decide : (0x30 : UInt8) ≤ 0x31) hnonzero.1, hnonzero.2⟩
      rcases digits_run_sound hd hds hp with ⟨hr, hm, hij, hj⟩
      refine ⟨?_, hij, hj⟩
      rw [bytesAt_of_some hd] at hr ⊢
      exact .pos hnonzero.1 hnonzero.2 hr hm
    · contradiction
  · contradiction

theorem parseInt_positive {b : ByteArray} {i : Nat} {d : UInt8}
    (hb : b[i]? = some d) (hl : 0x31 ≤ d) (hh : d ≤ 0x39) :
    parseInt b i = (digits b i 0).map (fun (n, j) => ((n : Int), j)) := by
  unfold parseInt
  split
  · rename_i he
    have he' : d = 0x30 := Option.some.inj (hb.symm.trans he)
    subst d
    simp at hl
  · rename_i he
    have he' : d = 0x2D := Option.some.inj (hb.symm.trans he)
    subst d
    simp at hl
  · rename_i d' hneq0 hneqminus he
    have he' : d' = d := Option.some.inj (he.symm.trans hb)
    subst d'
    simp [hl, hh]
  · rename_i he
    simp [hb] at he

theorem parseInt_complete {b : ByteArray} {i : Nat} {n : Int} {rest : List UInt8}
    (h : FvapiSpec.Json.IntLit (bytesAt b i) n rest) :
    ∃ j, parseInt b i = some (n, j) ∧ bytesAt b j = rest := by
  generalize hcs : bytesAt b i = cs at h
  cases h with
  | zero =>
    have h0 := (bytesAt_cons_iff b i 0x30 _).mp hcs
    exact ⟨i + 1, by simp [parseInt, h0.1], h0.2⟩
  | pos hl hh hd hn =>
    have h0 := (bytesAt_cons_iff b i _ _).mp hcs
    rw [← hcs] at hd
    rcases digits_complete (digitRun_tail hd) hn with ⟨j, hp, hr⟩
    exact ⟨j, by rw [parseInt_positive h0.1 hl hh, hp]; rfl, hr⟩
  | neg hl hh hd hn =>
    have h0 := (bytesAt_cons_iff b i 0x2D _).mp hcs
    have h1 := (bytesAt_cons_iff b (i + 1) _ _).mp h0.2
    rw [← h0.2] at hd
    rcases digits_complete (digitRun_tail hd) hn with ⟨j, hp, hr⟩
    exact ⟨j, by simp [parseInt, h0.1, h1.1, hl, hh, hp], hr⟩

end FvapiProof.Json
