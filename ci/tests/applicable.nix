# The applicability walk (den-hoag-b6nyh U1, `lib/applicable.nix`): what Nix can apply, and the
# head the argument meets. Every expectation is written by hand. A reached head is shown by applying
# it to 41, since a function has no equality; the leaf answers 42. `tests` holds the verdicts, heads,
# readers and kind texts; `testsError` pins that `applicablePatternOf` refuses an unapplicable value
# by `patternOf`'s name, catchably.
{ genPrelude, ... }:
let
  inherit (genPrelude)
    applicability
    applicableKindOf
    applicableLevels
    applicablePatternOf
    isApplicable
    ;

  leaf = x: x + 1;
  # `n` `__functor` steps above `leaf`.
  chain = n: if n == 0 then leaf else { __functor = _: chain (n - 1); };
  self =
    let
      s = {
        __functor = s: s;
      };
    in
    s;
  values = {
    lambda = leaf;
    plain = {
      __functor = _: leaf;
    };
    nested = {
      __functor = _: { __functor = _: leaf; };
    };
    # `__functor` is itself a functor, so Nix pushes twice.
    functorValued = {
      __functor = {
        __functor = _: _: leaf;
      };
    };
    chain31 = chain 31;
    chain32 = chain 32;
    chain33 = chain 33;
    inherit self;
    int = 5;
    toInt = {
      __functor = _: 5;
    };
    # `__functor` patterns the pushed set cannot bind: a missing required formal, and an extra
    # attribute (`__functor`) where the pattern has no `...`.
    requiresY = {
      __functor = { y }: leaf;
    };
    defaultsY = {
      __functor =
        {
          y ? 1,
        }:
        leaf;
    };
    # The same mismatch one step down, where the walk (not the one-step case) meets it.
    deepRequiresY = {
      __functor = _: { __functor = { y }: leaf; };
    };
    # Patterns the pushed set binds.
    ellipsis = {
      __functor = { ... }: leaf;
    };
    namesFunctor = {
      __functor = { __functor }: leaf;
    };
  };

  verdicts = builtins.mapAttrs (_: v: (applicability v).verdict) values;
  # The head applied to 41 where the verdict is true, else the record itself.
  reached =
    v:
    let
      a = applicability v;
    in
    if a.verdict == true then a.head 41 else a;
  refused = {
    verdict = false;
    head = null;
  };
  exhausted = {
    verdict = null;
    head = null;
  };
  bound = "a functor that reaches no function within 32 `__functor` steps";
  refusal = msg: {
    type = "ThrownError";
    msg = "^gen-prelude[.]patternOf: ${msg}$";
  };
in
{
  flake.tests.applicable = {
    # The ten tabled verdicts (spec §3a A8), and the two pattern-mismatch functors and their twins.
    test-verdicts = {
      expr = verdicts;
      expected = {
        lambda = true;
        plain = true;
        nested = true;
        functorValued = true;
        chain31 = true;
        chain32 = true;
        chain33 = null;
        self = null;
        int = false;
        toInt = false;
        requiresY = false;
        defaultsY = false;
        deepRequiresY = false;
        ellipsis = true;
        namesFunctor = true;
      };
    };

    # The head is the function the argument meets.
    test-the-head-applies-as-the-value-does = {
      expr = map reached [
        values.lambda
        values.plain
        values.nested
        values.functorValued
        values.chain31
        values.chain32
        values.ellipsis
      ];
      expected = [
        42
        42
        42
        42
        42
        42
        42
      ];
    };
    # And it agrees with Nix's own application of the value.
    test-the-head-is-what-nix-applies = {
      expr = map (v: v 41) [
        values.nested
        values.functorValued
        values.chain32
      ];
      expected = [
        42
        42
        42
      ];
    };

    test-a-refused-or-exhausted-walk-has-no-head = {
      expr = map reached [
        values.int
        values.toInt
        values.requiresY
        values.defaultsY
        values.chain33
        values.self
      ];
      expected = [
        refused
        refused
        refused
        refused
        exhausted
        exhausted
      ];
    };

    # The bool: an exhausted walk is false, never null, so `if isApplicable f` is total.
    test-isApplicable-is-the-bool = {
      expr = map isApplicable [
        values.chain33
        values.self
        values.int
        values.lambda
        values.requiresY
        values.nested
      ];
      expected = [
        false
        false
        false
        true
        false
        true
      ];
    };

    test-the-bound-is-32 = {
      expr = applicableLevels;
      expected = 32;
    };

    # The pattern is read on the value where `isFunction` holds, so a published `__functionArgs` is
    # honoured, and on the reached head otherwise.
    test-applicablePatternOf-reads-the-head = {
      expr =
        map
          (v: {
            inherit (applicablePatternOf v) kind formals ellipsis;
          })
          [
            values.lambda
            values.nested
            { __functor = _: { __functor = _: { x }: x; }; }
            {
              __functor = _: leaf;
              __functionArgs = {
                a = true;
              };
            }
          ];
      expected = [
        {
          kind = "named";
          formals = { };
          ellipsis = false;
        }
        {
          kind = "named";
          formals = { };
          ellipsis = false;
        }
        {
          kind = "set";
          formals = {
            x = false;
          };
          ellipsis = false;
        }
        {
          kind = "named";
          formals = {
            a = true;
          };
          ellipsis = false;
        }
      ];
    };

    # The kind a door names on its refusal path: the bound where the walk exhausted it, the type
    # otherwise.
    test-applicableKindOf = {
      expr = map applicableKindOf [
        values.chain33
        values.self
        values.toInt
        values.requiresY
        values.int
      ];
      expected = [
        bound
        bound
        "a set"
        "a set"
        "a int"
      ];
    };
  };

  flake.testsError.applicable = {
    test-applicablePatternOf-refuses-a-functor-to-a-non-function = {
      expr = applicablePatternOf values.toInt;
      expectedError = refusal "the argument is not a function by prelude[.]isFunction [(]its type is null[)]";
    };
    test-applicablePatternOf-refuses-an-exhausted-walk = {
      expr = applicablePatternOf values.chain33;
      expectedError = refusal "the argument is not a function by prelude[.]isFunction [(]its type is null[)]";
    };
    test-applicablePatternOf-refuses-a-non-function = {
      expr = applicablePatternOf values.int;
      expectedError = refusal "the argument is not a function by prelude[.]isFunction [(]its type is null[)]";
    };
  };
}
