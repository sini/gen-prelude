# The applicability walk (den-hoag-b6nyh U1, `lib/applicable.nix`): what Nix can apply, and the
# head the argument meets. Every expectation is written by hand. A reached head is shown by applying
# it to 41, since a function has no equality; the leaf answers 42. `tests` holds the verdicts, heads,
# readers and kind texts; `testsError` pins that `applicablePatternOf` refuses an unapplicable value
# by `patternOf`'s name, catchably. `readers-*` pin `isFunction` / `functionArgs`, the walk's verdict.
{ genPrelude, ... }:
let
  inherit (genPrelude)
    applicability
    applicableKindOf
    applicableLevels
    applicablePatternOf
    functionArgs
    isApplicable
    isFunction
    ;

  leaf = x: x + 1;
  # `n` `__functor` steps above `leaf`.
  chain = n: if n == 0 then leaf else { __functor = _: chain (n - 1); };
  # `n` steps where each `__functor` IS the next functor (the other chain shape).
  functorValuedChain =
    n:
    let
      u = d: if d == 1 then (_: leaf) else { __functor = _: u (d - 1); };
    in
    {
      __functor = u n;
    };
  # nixpkgs `lib.setFunctionArgs`, written out (gen-prelude has no nixpkgs).
  sFA = f: args: {
    __functor = _: f;
    __functionArgs = args;
  };
  # nixpkgs issue #574571's cases a and b, a functor-valued `__functor`, and `setFunctionArgs` over
  # a functor: each one Nix applies.
  nestedReaders = [
    { __functor = self: { __functor = self: x: x; }; }
    {
      __functor = {
        __functor =
          self1: self2: x:
          x;
      };
    }
    {
      __functor = {
        __functor = _: _: leaf;
      };
    }
    (sFA (sFA leaf { }) { })
  ];
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
  unbounded = reader: {
    type = "ThrownError";
    msg = "^gen-prelude[.]${reader}: a functor that reaches no function within 32 `__functor` steps$";
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
      expectedError = unbounded "isFunction";
    };
    test-applicablePatternOf-refuses-a-non-function = {
      expr = applicablePatternOf values.int;
      expectedError = refusal "the argument is not a function by prelude[.]isFunction [(]its type is null[)]";
    };
  };

  # `isFunction` and `functionArgs` give nixpkgs' answer (after nixpkgs PR #574597) on a nested
  # functor, the four values of nixpkgs issue #574571 and its fix, and on a chain of exactly the
  # bound in both shapes (den-hoag-b6nyh G4, G5).
  flake.tests.readers-nested = {
    test-isFunction-reads-a-nested-functor = {
      expr = map isFunction nestedReaders;
      expected = [
        true
        true
        true
        true
      ];
    };
    test-isFunction-serves-a-chain-at-the-bound = {
      expr = map isFunction [
        values.chain32
        (functorValuedChain 32)
      ];
      expected = [
        true
        true
      ];
    };
    test-functionArgs-reads-a-nested-functor = {
      expr = map functionArgs (nestedReaders ++ [ values.chain32 ]);
      expected = [
        { }
        { }
        { }
        { }
        { }
      ];
    };
    # A `__functionArgs` published one returned level down is honoured, as nixpkgs' is.
    test-functionArgs-reads-a-map-published-below = {
      expr = functionArgs {
        __functor = _: sFA leaf { x = false; };
      };
      expected = {
        x = false;
      };
    };
  };

  # Beyond the bound nixpkgs overflows the stack; each reader refuses by name, catchably (G5, G9).
  flake.testsError.readers-bound = {
    test-isFunction-refuses-a-self-functor = {
      expr = isFunction values.self;
      expectedError = unbounded "isFunction";
    };
    test-isFunction-refuses-a-chain-past-the-bound = {
      expr = isFunction values.chain33;
      expectedError = unbounded "isFunction";
    };
    test-functionArgs-refuses-a-chain-past-the-bound = {
      expr = functionArgs values.chain33;
      expectedError = unbounded "functionArgs";
    };
    test-functionArgs-refuses-a-self-functor = {
      expr = functionArgs values.self;
      expectedError = unbounded "functionArgs";
    };
  };
}
