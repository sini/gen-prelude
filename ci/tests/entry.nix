# THE STANDALONE ENTRY, AND WHAT A ZERO-DEPENDENCY LEAF OWES.
#
# gen-prelude depends on nothing, so its root is a bare VALUE rather than a function of a substrate:
# there is no bag to read, no lock to defer to and no default to force. The uniform entry call is
# therefore ARITY-DISPATCHED — `if builtins.isFunction v then v { } else v` — and the literal
# `import ./. { }` is WRONG here by design, aborting `expected a set but found a function`'s mirror,
# `attempt to call something which is not a function but a set`. That is the shape this cell pins.
#
# What is asserted is both halves at once, because either alone is satisfiable by the wrong root: the
# root is NOT a function, and the value it forwards is the one the flake path publishes.
{ genPrelude, ... }:
let
  entry = import ../..;
  dispatched = if builtins.isFunction entry then entry { } else entry;
in
{
  flake.tests.entry.test-the-root-is-a-bare-value-carrying-the-flake-surface = {
    expr = {
      isFunction = builtins.isFunction entry;
      names = builtins.attrNames dispatched;
    };
    expected = {
      isFunction = false;
      names = builtins.attrNames genPrelude;
    };
  };
}
