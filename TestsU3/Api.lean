import Fvapi.Json
import Fvapi.Hash.Sha256
import TestsU3.Boundary

namespace TestsU3.Api

private partial def toApi : Value → Fvapi.Json.Value
  | .null => .null
  | .bool b => .bool b
  | .int n => .int n
  | .str s => .str s
  | .arr xs => .arr (xs.map toApi)
  | .obj ms => .obj (ms.map fun (k, v) => (k, toApi v))

private partial def fromApi : Fvapi.Json.Value → Value
  | .null => .null
  | .bool b => .bool b
  | .int n => .int n
  | .str s => .str s
  | .arr xs => .arr (xs.map fromApi)
  | .obj ms => .obj (ms.map fun (k, v) => (k, fromApi v))

private def decode (bs : ByteArray) : Outcome :=
  match Fvapi.Json.decode bs with
  | .ok v => .ok (fromApi v)
  | .error .malformed => .error .malformed
  | .error .tooLarge => .error .tooLarge
  | .error .duplicateKey => .error .duplicateKey

def json : JsonApi where
  decode := decode
  print v := Fvapi.Json.print (toApi v)
  object ms := fromApi (Fvapi.Json.Value.object (ms.map fun (k, v) => (k, toApi v)))
  get? k v := ((toApi v).get? k).map fromApi
  asStr? v := (toApi v).asStr?
  asInt? v := (toApi v).asInt?
  asBool? v := (toApi v).asBool?
  asArr? v := ((toApi v).asArr?).map (List.map fromApi)
  asObj? v := ((toApi v).asObj?).map (List.map fun (k, x) => (k, fromApi x))
  equal a b := toApi a == toApi b

def hash : HashApi where
  State := Fvapi.Hash.Sha256.State
  hash := Fvapi.Hash.sha256
  init := Fvapi.Hash.Sha256.init
  update := Fvapi.Hash.Sha256.update
  finish := Fvapi.Hash.Sha256.finish
  ofReader := Fvapi.Hash.Sha256.ofReader
  file := Fvapi.Hash.sha256File
  hex := Fvapi.Hash.hex

end TestsU3.Api
