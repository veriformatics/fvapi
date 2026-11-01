namespace Fvapi.Hash

/-- SHA-256 of the bytes (32 bytes), by HACL*'s verified C (`docs/contracts/U3-codecs.md` S3;
`c/fvapi_sha256.c`). -/
@[extern "fvapi_sha256"]
opaque sha256 (input : @& ByteArray) : ByteArray

namespace Sha256

@[extern "fvapi_sha256_init"]
private opaque initState : Unit → ByteArray

/-- Hashes the whole blocks `data[off, off + len)` into the chaining state (`len` a multiple of
64, the span inside `data`: the C side aborts otherwise). -/
@[extern "fvapi_sha256_absorb"]
private opaque absorb (h : ByteArray) (data : @& ByteArray) (off len : USize) : ByteArray

/-- The digest from a chaining state, the < 64 trailing bytes and the total byte count. -/
@[extern "fvapi_sha256_squeeze"]
private opaque squeeze (h : @& ByteArray) (tail : @& ByteArray) (total : UInt64) : ByteArray

/-- Streaming state as a plain value: HACL's chaining words, the bytes of the current partial
block, and every byte count fed. No mutable object is shared. -/
structure State where
  private mk ::
  private h : ByteArray
  private tail : ByteArray
  private total : Nat

def init : State := ⟨initState (), .empty, 0⟩

/-- Feeds `data`: whole blocks go to HACL, the remainder waits in `tail`. -/
def update (s : State) (data : @& ByteArray) : State :=
  let total := s.total + data.size
  if s.tail.size + data.size < 64 then
    ⟨s.h, s.tail ++ data, total⟩
  else
    let fill := 64 - s.tail.size
    let (h, start) :=
      if s.tail.isEmpty then (s.h, 0)
      else (absorb s.h (s.tail ++ data.extract 0 fill) 0 64, fill)
    let whole := (data.size - start) / 64 * 64
    ⟨absorb h data start.toUSize whole.toUSize, data.extract (start + whole) data.size, total⟩

def finish (s : State) : ByteArray := squeeze s.h s.tail s.total.toUInt64

/-- SHA-256 of every chunk `read` returns until an empty one; a read error propagates (never a
digest of a prefix). -/
def ofReader (read : IO ByteArray) : IO ByteArray := do
  let mut s := init
  repeat
    let chunk ← read
    if chunk.isEmpty then break
    s := update s chunk
  return finish s

end Sha256

/-- SHA-256 of a file's bytes, read in 1 MiB chunks. -/
def sha256File (path : System.FilePath) : IO ByteArray :=
  IO.FS.withFile path .read fun h => Sha256.ofReader (h.read (1024 * 1024))

/-- One lowercase hex digit of `n < 16`. -/
def hexDigit (n : UInt8) : Char :=
  Char.ofNat (if n < 10 then 0x30 + n.toNat else 0x57 + n.toNat)

/-- Each byte as exactly two lowercase hex digits, high nibble first. -/
def hex (b : ByteArray) : String :=
  b.foldl (fun s x => (s.push (hexDigit (x >>> 4))).push (hexDigit (x &&& 15))) ""

end Fvapi.Hash
