import FvapiSpec.Hash

namespace FvapiSelf.Hash

/-- S3: `hex` renders each byte as exactly two lowercase hex digits, high nibble first. -/
def HexExact : Prop :=
  ∀ b : ByteArray, (Fvapi.Hash.hex b).toList = FvapiSpec.Hash.hexChars b.data.toList

end FvapiSelf.Hash
