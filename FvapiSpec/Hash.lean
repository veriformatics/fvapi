import Fvapi.Hash.Sha256

/-! Reviewed vocabulary for fvapi's hex rendering (`docs/contracts/U3-codecs.md` S3). -/

namespace FvapiSpec.Hash

/-- The sixteen lowercase hex digits, in value order. -/
def hexAlphabet : List Char := "0123456789abcdef".toList

/-- Each byte as two lowercase hex digits, high nibble first. -/
def hexChars (bs : List UInt8) : List Char :=
  bs.flatMap fun x => [hexAlphabet.getD (x.toNat / 16) '?', hexAlphabet.getD (x.toNat % 16) '?']

end FvapiSpec.Hash
