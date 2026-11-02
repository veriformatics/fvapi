import TestsU3B.Api

set_option autoImplicit false

def main (args : List String) : IO UInt32 :=
  TestsU3B.tasksMain TestsU3B.Api.port args
