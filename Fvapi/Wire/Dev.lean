import Fvapi.Wire.Decide
import Fvapi.Wire.Records
import Fvapi.Hash.Sha256

namespace Fvapi.Wire.Dev

open Fvapi.Json

private def emit (v : Value) : IO Unit := IO.println (String.fromUTF8! (Fvapi.Json.print v))

private def requestPayload (req : Request) : Value :=
  .object ([⟨"query", req.query⟩] ++ match req.body with
    | .none => []
    | .json v => [("body", v)]
    | .bytes b => [("body_hex", .str (Fvapi.Hash.hex b))])

private def responsePayload : Response → Value
  | .json v => v
  | .bytes b => .object [("body_hex", .str (Fvapi.Hash.hex b))]

private def requestResult (route : Route) : Except Failure Request → Value
  | .ok req => .object [("ok", requestPayload req)]
  | .error failure =>
      let e := (renderError route failure).getD ⟨500, "internal"⟩
      .object [("status", .int e.status), ("error", .str e.code)]

private def responseResult : ResponseResult → Value
  | .ok res => .object [("ok", responsePayload res)]
  | .badResponse => .object [("outcome", .str "bad_response")]
  | .unsupported names => .object [("outcome", .str "unsupported"),
      ("features", .arr (names.map Value.str))]

private def hexNibble? (c : Char) : Option UInt8 :=
  if '0' ≤ c ∧ c ≤ '9' then some (c.toNat - '0'.toNat).toUInt8
  else if 'a' ≤ c ∧ c ≤ 'f' then some (c.toNat - 'a'.toNat + 10).toUInt8
  else none

private def fromHex? (text : String) : Option ByteArray := do
  let rec loop : List Char → ByteArray → Option ByteArray
    | [], acc => some acc
    | a :: b :: rest, acc => do
        let hi ← hexNibble? a
        let lo ← hexNibble? b
        loop rest (acc.push (hi * 16 + lo))
    | _, _ => none
  loop text.toList ByteArray.empty

/-- The driver envelope is not an API message: a 64 KiB byte body needs 128 KiB of hex.
Only this dev-input parser omits the string cap. The actual JSON body is rechecked by J3. -/
private def driverPayload? (bytes : ByteArray) : Option Value := do
  if Fvapi.Json.maxDepth < Fvapi.Json.scanDepth bytes then none else do
    let (v, endIndex) ← Fvapi.Json.parseValue bytes (2 * bytes.size + 2)
      (Fvapi.Json.skipWs bytes 0)
    if Fvapi.Json.skipWs bytes endIndex ≠ bytes.size ∨ Fvapi.Json.hasDupKey v then none
    else some (Fvapi.Json.canon v)

private def sameBody (a b : Body) : Bool :=
  match a, b with
  | .none, .none => true
  | .json x, .json y => decide (x = y)
  | .bytes x, .bytes y => decide (x = y)
  | _, _ => false

private def sameResponse (a b : Response) : Bool :=
  match a, b with
  | .json x, .json y => decide (x = y)
  | .bytes x, .bytes y => decide (x = y)
  | _, _ => false

private def normalizedRequest? (route : Route) (payload : Value) : Option Request := do
  let query ← payload.get? "query"
  let members ← payload.asObj?
  let body ← match (routeTable route).requestMode with
    | .none => do
      unless members.map Prod.fst = ["query"] do none
      pure Body.none
    | .json => do
      unless members.map Prod.fst = ["body", "query"] do none
      (payload.get? "body").map Body.json
    | .bytes => do
      unless members.map Prod.fst = ["body_hex", "query"] do none
      let text ← (payload.get? "body_hex").bind Value.asStr?
      pure (Body.bytes (← fromHex? text))
  let req : Request := ⟨query, body⟩
  let encoded := encodeRequest req
  match decideRequest route encoded.query encoded.body with
  | .ok normalized =>
    if normalized.query = query ∧ sameBody normalized.body body then some req else none
  | .error _ => none

private def normalizedResponse? (route : Route) (status : Nat) (payload : Value) :
    Option Response := do
  let res ← if route = .bundle ∧ status = 200 then do
      let members ← payload.asObj?
      if members.map Prod.fst ≠ ["body_hex"] then none else do
        let text ← (payload.get? "body_hex").bind Value.asStr?
        return Response.bytes (← fromHex? text)
    else some (.json payload)
  match decideResponse route status (encodeResponse res) with
  | .ok normalized => if sameResponse normalized res then some res else none
  | _ => none

private def status? (s : String) : Option Nat := do
  let n ← s.toNat?
  if toString n = s ∧ 100 ≤ n ∧ n ≤ 599 then some n else none

def usage : String :=
  "usage: fvapi dev wire request ROUTE [--query Q]\n" ++
  "       fvapi dev wire response ROUTE STATUS\n" ++
  "       fvapi dev wire encode-request ROUTE\n" ++
  "       fvapi dev wire encode-response ROUTE STATUS\n"

/-- Usage alone exits 2; an accepted invocation decides every input and exits 0. -/
def run (args : List String) : IO UInt32 := do
  let invocation ← match args with
    | ["request", name] => pure (some (0, name, "", 0))
    | ["request", name, "--query", query] => pure (some (0, name, query, 0))
    | ["response", name, status] => pure ((status? status).map fun n => (1, name, "", n))
    | ["encode-request", name] => pure (some (2, name, "", 0))
    | ["encode-response", name, status] =>
        pure ((status? status).map fun n => (3, name, "", n))
    | _ => pure none
  let some (mode, name, query, status) := invocation | IO.eprint usage; return 2
  let some route := Route.ofString? name | IO.eprint usage; return 2
  let input ← (← IO.getStdin).readBinToEnd
  match mode with
  | 0 => emit (requestResult route (decideRequest route query.toUTF8 input)); return 0
  | 1 => emit (responseResult (decideResponse route status input)); return 0
  | 2 =>
    let some payload := driverPayload? input | IO.eprint usage; return 2
    let some req := normalizedRequest? route payload | IO.eprint usage; return 2
    let encoded := encodeRequest req
    emit (.object [("query_string", .str (String.fromUTF8! encoded.query)),
      ("body_hex", .str (Fvapi.Hash.hex encoded.body))])
    return 0
  | _ =>
    let some payload := driverPayload? input | IO.eprint usage; return 2
    let some res := normalizedResponse? route status payload | IO.eprint usage; return 2
    emit (.object [("body_hex", .str (Fvapi.Hash.hex (encodeResponse res)))])
    return 0

end Fvapi.Wire.Dev
