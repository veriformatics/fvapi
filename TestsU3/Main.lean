import TestsU3.Api
import TestsU3.Runner

/-- Native package boundary; run.sh maps process crashes to rc 3. -/
def main (args : List String) : IO UInt32 :=
  TestsU3.Runner.main TestsU3.Api.json TestsU3.Api.hash args
