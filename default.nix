# gen-prelude is pure — it takes no inputs (no nixpkgs lib, no deps) and ignores any
# args passed for calling-convention parity with the other gen libraries.
{ ... }: import ./lib { }
