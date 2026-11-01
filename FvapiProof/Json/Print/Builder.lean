import FvapiSelf.Json

namespace FvapiProof.Json

open Fvapi.Json FvapiSpec.Json

@[simp] theorem bytes_push (out : ByteArray) (b : UInt8) :
    (out.push b).data.toList = out.data.toList ++ [b] := by
  simp

theorem foldl_push_bytes (xs : List UInt8) (out : ByteArray) :
    (xs.foldl ByteArray.push out).data.toList = out.data.toList ++ xs := by
  induction xs generalizing out with
  | nil => simp
  | cons x xs ih => simp [ih, List.append_assoc]

theorem pushChar_exact (out : ByteArray) (c : Char) :
    (pushChar out c).data.toList = out.data.toList ++ escapeChar c := by
  unfold pushChar escapeChar
  repeat' first
    | split
    | simp_all [hexByte, hexDigit, foldl_push_bytes, List.append_assoc]

theorem foldl_pushChar (cs : List Char) (out : ByteArray) :
    (cs.foldl pushChar out).data.toList = out.data.toList ++ cs.flatMap escapeChar := by
  induction cs generalizing out with
  | nil => simp
  | cons c cs ih => simp [ih, pushChar_exact, List.append_assoc]

theorem pushStr_exact (out : ByteArray) (s : String) :
    (pushStr out s).data.toList = out.data.toList ++ strText s := by
  simp [pushStr, String.foldl_eq_foldl_toList, foldl_pushChar, strText, List.append_assoc]

theorem foldl_pushDigit (cs : List Char) (out : ByteArray) :
    (cs.foldl (fun o c => o.push c.toNat.toUInt8) out).data.toList =
      out.data.toList ++ cs.map (fun c => c.toNat.toUInt8) := by
  induction cs generalizing out with
  | nil => simp
  | cons c cs ih => simp [ih, List.append_assoc]

theorem pushInt_exact (out : ByteArray) (n : Int) :
    (pushInt out n).data.toList = out.data.toList ++ intText n := by
  unfold pushInt intText
  split <;> simp [foldl_pushDigit, List.append_assoc]

mutual
theorem printTo_exact (out : ByteArray) : (v : Value) →
    (printTo out v).data.toList = out.data.toList ++ canonical v
  | .null => by simp [printTo, canonical, List.append_assoc]
  | .bool true => by simp [printTo, canonical, List.append_assoc]
  | .bool false => by simp [printTo, canonical, List.append_assoc]
  | .int n => by simp [printTo, canonical, pushInt_exact]
  | .str s => by simp [printTo, canonical, pushStr_exact]
  | .arr xs => by
    rw [printTo, bytes_push, printList_exact (out.push 0x5B) xs]
    simp [canonical, List.append_assoc]
  | .obj ms => by
    rw [printTo, bytes_push, printMembers_exact (out.push 0x7B) ms]
    simp [canonical, List.append_assoc]
termination_by v => sizeOf v

theorem printList_exact (out : ByteArray) : (xs : List Value) →
    (printList out xs).data.toList = out.data.toList ++ canonicalList xs
  | [] => by simp [printList, canonicalList]
  | [v] => by simpa only [printList, canonicalList] using printTo_exact out v
  | v :: w :: vs => by
    rw [printList, printList_exact ((printTo out v).push 0x2C) (w :: vs),
      bytes_push, printTo_exact out v]
    all_goals simp [canonicalList, List.append_assoc]
termination_by xs => sizeOf xs

theorem printMembers_exact (out : ByteArray) : (ms : List (String × Value)) →
    (printMembers out ms).data.toList = out.data.toList ++ canonicalMembers ms
  | [] => by simp [printMembers, canonicalMembers]
  | [(k, v)] => by
    rw [printMembers, printTo_exact ((pushStr out k).push 0x3A) v]
    simp [canonicalMembers, pushStr_exact, List.append_assoc]
  | (k, v) :: p :: ms => by
    rw [printMembers,
      printMembers_exact ((printTo ((pushStr out k).push 0x3A) v).push 0x2C) (p :: ms),
      bytes_push, printTo_exact ((pushStr out k).push 0x3A) v]
    all_goals simp [canonicalMembers, pushStr_exact, List.append_assoc]
termination_by ms => sizeOf ms
end

end FvapiProof.Json
