# gen-prelude REPL — all exports in scope, aliased as p.
let
  genPrelude = import ../lib { };
in
{
  inherit genPrelude;
  p = genPrelude;
}
// genPrelude
