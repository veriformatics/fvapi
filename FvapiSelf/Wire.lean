import Fvapi.Wire.Decide
import FvapiSpec.Wire

namespace FvapiSelf.Wire

open Fvapi.Wire

/-- W3: exact ordered pure server decision, for all raw query/body bytes. -/
def RequestExact : Prop :=
  ∀ route query body result, decideRequest route query body = result ↔
    FvapiSpec.Wire.RequestOutcome route query body result

/-- W3: exact client decision, including raw bytes, feature failures and rejected envelopes. -/
def ResponseExact : Prop :=
  ∀ route status body result, decideResponse route status body = result ↔
    FvapiSpec.Wire.ResponseOutcome route status body result

/-- W3: complete normalized requests round-trip; each body mode has its own byte law. -/
def RequestEncode : Prop :=
  ∀ route req, FvapiSpec.Wire.RequestAdmissible route req →
    let encoded := encodeRequest req
    decideRequest route encoded.query encoded.body = .ok req ∧
    FvapiSpec.Wire.requestBodyLaw req.body encoded

/-- W3: supported complete responses round-trip to known fields; raw bytes stay exact. -/
def ResponseEncode : Prop :=
  ∀ route status res, FvapiSpec.Wire.ResponseAdmissible route status res →
    decideResponse route status (encodeResponse res) =
      .ok (FvapiSpec.Wire.projectResponse route status res) ∧
    FvapiSpec.Wire.responseBodyLaw res (encodeResponse res)

/-- W3: internal failure identity, route, status and wire code are bound together. -/
def StatusExact : Prop :=
  ∀ route failure, renderError route failure = FvapiSpec.Wire.reviewedError route failure

end FvapiSelf.Wire
