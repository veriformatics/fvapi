import FvapiSpec.Wire

namespace FvapiSpec.Wire

open Fvapi.Wire

def isRecord : Schema → Bool
  | .record _ _ => true
  | _ => false

mutual
/-- Schema instances carry finite bounds and unique field/tag names. -/
def schemaWellFormed : Schema → Bool
  | .scalar _ => true
  | .array lo hi item => lo ≤ hi && schemaWellFormed item
  | .record fields _ => decide (fields.map Prod.fst).Nodup && fieldsWellFormed fields
  | .tagged _ branches => !branches.isEmpty && decide (branches.map Prod.fst).Nodup &&
      branchesWellFormed branches
def fieldsWellFormed : List Field → Bool
  | [] => true
  | (name, _, schema) :: rest => name.utf8ByteSize ≤ 65536 && schemaWellFormed schema &&
      fieldsWellFormed rest
def branchesWellFormed : List (String × Schema) → Bool
  | [] => true
  | (_, schema) :: rest => schemaWellFormed schema && branchesWellFormed rest
end

def queryKindEncodable : Scalar → Bool
  | .nat | .pos | .ident | .token | .cursor => true
  | .boundedNat lo hi => lo ≤ hi && hi ≤ 9007199254740991
  | .oneOf values => values.all fun s => !s.isEmpty && s.toUTF8.data.toList.all queryByte
  | _ => false

def tableAdmissible (route : Route) : Bool :=
  let table := reviewedTable route
  schemaWellFormed table.requestSchema && decide (table.query.map (·.name)).Nodup &&
    table.query.all (fun f => !f.name.isEmpty && f.name.toUTF8.data.toList.all queryByte &&
      queryKindEncodable f.kind) &&
    (table.requestMode != .json || isRecord table.requestSchema) &&
    table.responses.all (fun response => schemaWellFormed response.schema &&
      (if response.mode = .json then isRecord response.schema
       else response.mode == .bytes && decide (route = .bundle) && response.status == 200))

end FvapiSpec.Wire
