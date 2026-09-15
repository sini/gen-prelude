# THE STANDALONE ENTRY, AND WHAT A ZERO-DEPENDENCY LEAF OWES.
#
# gen-prelude depends on nothing, but its root is a NULLARY FUNCTION rather than a bare value
# (den-hoag-iev2q, arm (a) of the leaf-entry fork): the uniform entry call across the whole
# roster is the literal `import ./. { }`, leaf or not, and it is total now rather than needing
# the old arity dispatch (`if builtins.isFunction v then v { } else v`) that a bare-value root
# forced on every caller. gen-prelude gaining a dependency later changes what the empty pattern
# defaults to, never the call text at this root.
#
# What is asserted is two-fold, because either alone is satisfiable by the wrong root: the root
# IS a function (not a value a caller could apply the literal to only by accident), and calling
# it with `{ }` forwards the value the flake path publishes.
#
# ★ THE THIRD HALF — that `{ }:` refuses an argument it does not declare, where `_:` would
# silently accept and drop one — is NOT a cell here. Measured on Nix 2.34.8: `builtins.tryEval`
# does not catch a "called with unexpected argument" abort (control: it DOES catch a plain
# `throw`), so a cell built on `tryEval (entry { x = 1; })` does not report a red — it crashes
# the whole suite's evaluation, the same class this ecosystem already tracks for the
# missing-attribute case (`gen/lib/mkGenLibs.nix`'s `input`) and for `iterateBounded`'s
# unguarded arm (AGENTS.md). That half is driven out-of-band instead:
# `nix-instantiate --eval -E 'import ./default.nix { x = 1; }'` ⇒ exit 1, `function 'anonymous
# lambda' called with unexpected argument 'x'` — verified at the leaf-build landing, not pinned
# as a cell that would abort the run it is meant to report on.
{ genPrelude, ... }:
let
  entry = import ../..;
in
{
  flake.tests.entry.test-the-root-is-a-nullary-function-carrying-the-flake-surface = {
    expr = {
      isFunction = builtins.isFunction entry;
      names = builtins.attrNames (entry { });
    };
    expected = {
      isFunction = true;
      names = builtins.attrNames genPrelude;
    };
  };
}
