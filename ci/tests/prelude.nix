# gen-prelude tests.
#
# `prelude` — readable literal-expectation sanity checks.
# `prelude-fidelity` — the load-bearing guard: every vendored utility must be
#   behavior-identical to nixpkgs `lib`, over normal + boundary inputs. `lib` here is
#   nixpkgs lib (the CI test runner has it; the lib itself does not). A consumer swaps
#   `lib.X` → `prelude.X` expecting identical semantics — these assert exactly that.
{ lib, genPrelude, ... }:
let
  p = genPrelude;
  xs = [
    3
    1
    1
    2
    3
    2
  ];
  attrs = {
    b = 2;
    a = 1;
    c = 3;
  };
  gt1 = _n: v: v > 1;
  # An `iterateBounded` state whose loop-carried field throws when forced: the pair of cases
  # below differ only in whether `strict` reaches it.
  ranOverBoom =
    strict: (builtins.tryEval (p.iterateBounded strict (st: st) { boom = throw "x"; } [ 1 ])).success;
  showKV = n: v: "${n}=${toString v}";
  idxShow = i: x: "${toString i}:${toString x}";

  # ── unique's parity oracle ──
  # The expression `unique` used to be, kept verbatim. Arms that say "agrees with the incumbent"
  # compare against THIS, evaluated in the same run, never against a remembered figure.
  incumbentUnique = builtins.foldl' (acc: x: if builtins.elem x acc then acc else acc ++ [ x ]) [ ];

  # `tryEval ∘ length` — the only instrument that observes HOW MUCH a construction forces. Every
  # other arm compares under `==`, which forces both sides and is therefore structurally blind to
  # strictness: a guard that evaluates an element the incumbent never touches passes all of them.
  forces =
    f: xs:
    let
      r = builtins.tryEval (builtins.length (f xs));
    in
    if r.success then toString r.value else "ABORT";

  # A context-carrying string: legal as a `unique` element, ILLEGAL as an attribute name. The
  # fixture exists so the keying is tested against a value no consumer sweep can rule out.
  ctxStr = "${derivation {
    name = "ctx-fixture";
    builder = "/bin/sh";
    system = "x86_64-linux";
  }}";

  # The value classes strictness parity is asserted over. Grouped by what each one can catch.
  strictnessClasses = {
    singletonBottom = [ (throw "BOOM") ]; # ★ the load-bearing case
    singletonUnforcedField = [ { a = throw "deep"; } ];
    emptyList = [ ];
    singletonString = [ "q" ];
    mixedStringInt = [
      "a"
      1
    ];
    intThenBottom = [
      1
      (throw "B")
    ];
    bottomThenInt = [
      (throw "A")
      1
    ];
    bottomThenString = [
      (throw "A")
      "b"
    ];
    stringThenBottom = [
      "a"
      (throw "B")
    ];
    twoBottoms = [
      (throw "A")
      (throw "B")
    ];
    stringsThenBottom = [
      "a"
      "b"
      (throw "C")
    ];
    equalAttrs = [
      { a = 1; }
      { a = 1; }
    ];
    attrs24 = builtins.genList (i: { v = i; }) 24;
    shuffledDups = [
      "c"
      "a"
      "b"
      "a"
      "c"
    ];
  };

  # ── escapeRegex's metacharacter set ──
  # An escape-set cell answers twice: against nixpkgs on the same inputs, and against the
  # answer written into the cell. The oracle alone would accept a needle/haystack pair gone
  # VACUOUS under a later edit — both sides agreeing for a boring reason, having stopped
  # exercising their member. The stated answer alone would not notice the copy drifting from
  # what it is a copy of.
  escCell = needle: haystack: answer: {
    expr = {
      prelude = p.hasInfix needle haystack;
      nixpkgs = lib.hasInfix needle haystack;
    };
    expected = {
      prelude = answer;
      nixpkgs = answer;
    };
  };

  # Every printable ASCII character, in code-point order. The byte-identity arm runs over
  # this rather than over a sample: a member ADDED to the set or DROPPED from it changes this
  # one string's escaping whichever character it is, so the arm needs no per-member case and
  # no call into the regex engine. Its scope is single characters in this range — a
  # hypothetical multi-character entry is not covered, and nixpkgs' set is
  # `stringToCharacters`-derived, so no such entry exists to cover.
  printableAscii = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
in
{
  flake.tests = {
    prelude = {
      test-genAttrs = {
        expr = p.genAttrs [ "a" "b" ] (n: n + "!");
        expected = {
          a = "a!";
          b = "b!";
        };
      };
      test-unique = {
        expr = p.unique xs;
        expected = [
          3
          1
          2
        ];
      };

      # ── unique: ORDER ──
      # First-occurrence order is what keeps the nixpkgs fidelity assertion true, so it is
      # asserted element-for-element. Comparing lengths or sorted contents would not test it.
      test-unique-order-shuffled = {
        expr = p.unique [
          "c"
          "a"
          "b"
          "a"
          "c"
          "c"
          "d"
          "b"
        ];
        expected = [
          "c"
          "a"
          "b"
          "d"
        ];
      };
      # ★ ORDER TRAPS. Both are designed to break a construction that sorts KEYS rather than
      #   first-occurrence INDICES: the first is in descending key order throughout, the second
      #   orders differently under string and numeric comparison. A key-sorting implementation
      #   returns ["a","w","x","y","z"] and ["1","10","2","9"] here and fails loudly.
      test-unique-order-not-key-sorted = {
        expr = p.unique [
          "z"
          "y"
          "x"
          "w"
          "z"
          "a"
        ];
        expected = [
          "z"
          "y"
          "x"
          "w"
          "a"
        ];
      };
      test-unique-order-numeric-strings = {
        expr = p.unique [
          "10"
          "9"
          "2"
          "10"
          "1"
        ];
        expected = [
          "10"
          "9"
          "2"
          "1"
        ];
      };
      test-unique-all-duplicates = {
        expr = p.unique [
          "x"
          "x"
          "x"
          "x"
        ];
        expected = [ "x" ];
      };
      test-unique-singleton = {
        expr = p.unique [ "q" ];
        expected = [ "q" ];
      };

      # ── unique: STRING CONTEXT ──
      # ★ A context-carrying string is a legal element and an illegal attribute name, so the key
      #   must discard context while the RESULT must keep it. `agrees` pins the partition (`==`
      #   ignores context, so the two copies collapse); `ctx` pins that the survivor is the
      #   caller's original value and not a rebuilt key. Without this arm the trap is untested,
      #   and it fails as an UNCATCHABLE abort rather than a wrong answer.
      test-unique-string-context = {
        expr =
          let
            input = [
              ctxStr
              ctxStr
              "plain"
            ];
            r = p.unique input;
          in
          {
            len = builtins.length r;
            ctx = builtins.hasContext (builtins.head r);
            agrees = r == incumbentUnique input;
          };
        expected = {
          len = 2;
          ctx = true;
          agrees = true;
        };
      };

      # ── unique: NON-STRING ROUTING ──
      # `unique` is total on its whole domain, and the fold is retained to keep it that way. Each
      # case asserts equality with the incumbent element-for-element, not merely that it does not
      # throw — a construction that narrows the domain to strings fails here loudly.
      test-unique-routes-ints = {
        expr = p.unique [
          1
          2
          2
          3
        ];
        expected = incumbentUnique [
          1
          2
          2
          3
        ];
      };
      test-unique-routes-lists = {
        expr = p.unique [
          [ 1 ]
          [ 1 ]
          [ 2 ]
        ];
        expected = incumbentUnique [
          [ 1 ]
          [ 1 ]
          [ 2 ]
        ];
      };
      test-unique-routes-attrs = {
        expr = p.unique [
          { a = 1; }
          { a = 1; }
          { b = 2; }
        ];
        expected = incumbentUnique [
          { a = 1; }
          { a = 1; }
          { b = 2; }
        ];
      };
      # ★ The guard is per-LIST, not per-element: a mixed list routes WHOLE to the fold. A
      #   per-element guard would dedupe the strings against a separate table and reorder.
      test-unique-routes-mixed-whole-list = {
        expr = p.unique [
          "a"
          1
          "a"
          1
        ];
        expected = incumbentUnique [
          "a"
          1
          "a"
          1
        ];
      };
      # ★ 24 attrset elements — the shape observed in real calls, and the one both proposed
      #   string-only restrictions would have aborted on.
      test-unique-routes-attrs24 = {
        expr = p.unique strictnessClasses.attrs24;
        expected = incumbentUnique strictnessClasses.attrs24;
      };
      test-unique-routes-attrs24-with-dups = {
        expr =
          let
            input = builtins.genList (i: { v = i - (i / 8) * 8; }) 24;
          in
          p.unique input == incumbentUnique input && builtins.length (p.unique input) == 8;
        expected = true;
      };

      # ── unique: STRICTNESS PARITY ──
      # ★ THE LOAD-BEARING CASE. `elem x [ ]` answers false without comparing, so the incumbent
      #   never forces the sole element of a singleton. A bare `all isString` guard does force it,
      #   turning a working call into an abort — which is why the length guard is part of the
      #   construction and not an optimisation. This case reads ABORT under that guard.
      test-unique-singleton-bottom-not-forced = {
        expr = forces p.unique [ (throw "BOOM") ];
        expected = "1";
      };
      # The same predicate over all 14 value classes, incumbent against candidate, in one run.
      test-unique-strictness-parity = {
        expr = builtins.mapAttrs (_: forces p.unique) strictnessClasses;
        expected = builtins.mapAttrs (_: forces incumbentUnique) strictnessClasses;
      };
      # Control on the same instrument in the same run: `forces` DOES report aborts, so the
      # parity above is a finding and not a predicate that could never have read ABORT.
      test-unique-strictness-instrument-control = {
        expr = forces p.unique [
          "a"
          (throw "B")
        ];
        expected = "ABORT";
      };

      # ── unique: the evaluator assumptions the construction rests on ──
      # Both silently invalidate the first-index table if a future evaluator changes them, and
      # neither is visible in any behavioural arm, so they are asserted rather than trusted.
      test-listToAttrs-keeps-first-binding = {
        expr = builtins.listToAttrs [
          {
            name = "a";
            value = 1;
          }
          {
            name = "a";
            value = 2;
          }
        ];
        expected = {
          a = 1;
        };
      };
      test-equality-ignores-string-context = {
        expr = ctxStr == builtins.unsafeDiscardStringContext ctxStr;
        expected = true;
      };
      # `unsafeDiscardStringContext` is internal: its name is a warning that should not be handed
      # to consumers casually. Control on the same predicate in the same run — the builtins this
      # library DOES re-export still answer true, so the absence is a finding.
      test-unsafeDiscardStringContext-not-exported = {
        expr = {
          leaked = p ? unsafeDiscardStringContext;
          control = p ? listToAttrs && p ? sort && p ? unique;
        };
        expected = {
          leaked = false;
          control = true;
        };
      };
      test-filterAttrs = {
        expr = p.filterAttrs gt1 attrs;
        expected = {
          b = 2;
          c = 3;
        };
      };
      test-fix = {
        expr =
          (p.fix (self: {
            a = 1;
            b = self.a + 1;
          })).b;
        expected = 2;
      };
      # `toposort` is retired: ordering has one owner, and it is gen-graph. The two cases
      # that stood here (`test-toposort-result`, `test-toposort-cycle-detected`) are
      # replaced by `order-front-door.test-topo-total-order` and
      # `order-front-door.test-topo-cycle-discriminated` in gen-graph's suite.
      test-toposort-not-exported = {
        expr = p ? toposort;
        expected = false;
      };
      # Control on the same predicate in the same run: `sort`, the primitive comparator
      # sort this library DOES keep, is still exported — so the absence above is a finding
      # and not a probe that could not have matched.
      test-sort-still-exported = {
        expr = p ? sort;
        expected = true;
      };
      test-last-empty-throws = {
        expr = (builtins.tryEval (p.last [ ])).success;
        expected = false;
      };
      # groupBy: partition xs by keyOf; within-group order stays input order.
      test-groupBy = {
        expr = p.groupBy (n: if n > 2 then "big" else "small") xs;
        expected = {
          small = [
            1
            1
            2
            2
          ];
          big = [
            3
            3
          ];
        };
      };
      test-groupBy-empty = {
        expr = p.groupBy (n: toString n) [ ];
        expected = { };
      };
      # Backtracking-free: hasInfix over a large string must not overflow the C stack
      # (nixpkgs `lib.hasInfix`'s `.*needle.*` regex does, at depth ∝ length). 40k chars.
      test-hasInfix-large-string-safe = {
        expr =
          let
            big = lib.concatStrings (builtins.genList (_: "abcdefghij") 4000);
          in
          [
            (p.hasInfix "needle" big)
            (p.hasInfix "abcdefghij" big)
          ];
        expected = [
          false
          true
        ];
      };
      # Collision stability: all three share a key and must keep input order.
      test-groupBy-collision-order = {
        expr = p.groupBy (s: builtins.substring 0 1 s) [
          "art"
          "ale"
          "arc"
        ];
        expected = {
          a = [
            "art"
            "ale"
            "arc"
          ];
        };
      };

      # dedupByKey: first-occurrence-wins by key; order-preserving.
      test-dedupByKey-first-occ = {
        expr = p.dedupByKey (n: n.k) [
          {
            k = "a";
            v = 1;
          }
          {
            k = "b";
            v = 2;
          }
          {
            k = "a";
            v = 3;
          }
        ];
        expected = [
          {
            k = "a";
            v = 1;
          }
          {
            k = "b";
            v = 2;
          }
        ];
      };
      # ★ NULL-KEEP (load-bearing): both null-key nodes survive; a null between two real dups
      #   neither evicts the later "a" nor is evicted — the second "a" is still dropped.
      test-dedupByKey-null-keep = {
        expr = p.dedupByKey (n: n.k) [
          {
            k = "a";
            id = 1;
          }
          {
            k = null;
            id = 2;
          }
          {
            k = null;
            id = 3;
          }
          {
            k = "a";
            id = 4;
          }
        ];
        expected = [
          {
            k = "a";
            id = 1;
          }
          {
            k = null;
            id = 2;
          }
          {
            k = null;
            id = 3;
          }
        ];
      };
      test-dedupByKey-empty = {
        expr = p.dedupByKey (n: n.k) [ ];
        expected = [ ];
      };
      # ★ NULL-KEEP, at EQUAL CONTENT (the case the arm above cannot make). The two keyless
      #   elements are indistinguishable, so an implementation that entered them into `seen` — or
      #   that deduped them structurally — collapses them to one and loses content silently. Both
      #   must survive, and the keyed duplicate must still go: the two directions are separate
      #   claims and this asserts them together.
      test-dedupByKey-null-equal-content-both-survive = {
        expr = p.dedupByKey (n: n.k) [
          {
            k = null;
            tag = "same";
          }
          {
            k = "a";
            tag = "keyed";
          }
          {
            k = null;
            tag = "same";
          }
          {
            k = "a";
            tag = "dropped";
          }
        ];
        expected = [
          {
            k = null;
            tag = "same";
          }
          {
            k = "a";
            tag = "keyed";
          }
          {
            k = null;
            tag = "same";
          }
        ];
      };
      # Stack safety, the property the re-expression exists for, and the reason it is not a
      # micro-optimisation: the naive `[ x ] ++ go … rest` recursion this replaces spent one
      # evaluator frame per element and aborted UNCATCHABLY past `max-call-depth` — measured, it
      # evaluated at 9,000 and died at 10,000, a ceiling inside the range of real inputs. 50,000
      # is five times that ceiling. Every step here is a primop, so there is no descent at all.
      test-dedupByKey-stack-safe-at-scale = {
        expr = builtins.length (
          p.dedupByKey (n: n.k) (builtins.genList (i: { k = "key-${toString i}"; }) 50000)
        );
        expected = 50000;
      };
      # Order is preserved across a mixed keyed/unkeyed input — the kept set is assembled from
      # two sources (the index table and the unkeyed positions) and must interleave by position,
      # not concatenate by source.
      test-dedupByKey-order-across-null-and-keyed = {
        expr = map (n: n.id) (
          p.dedupByKey (n: n.k) [
            {
              k = "b";
              id = 0;
            }
            {
              k = null;
              id = 1;
            }
            {
              k = "a";
              id = 2;
            }
            {
              k = "b";
              id = 3;
            }
            {
              k = null;
              id = 4;
            }
          ]
        );
        expected = [
          0
          1
          2
          4
        ];
      };

      # indexOf: first position or -1.
      test-indexOf-present = {
        expr = p.indexOf [ "a" "b" "c" ] "b";
        expected = 1;
      };
      test-indexOf-absent = {
        expr = p.indexOf [ "a" "b" ] "z";
        expected = -1;
      };
      test-indexOf-first = {
        expr = p.indexOf [ "a" "b" "a" ] "a";
        expected = 0;
      };

      # findFirst: readable literal checks (fidelity below also covers it).
      test-findFirst-match = {
        expr = p.findFirst (x: x > 2) 0 [
          1
          2
          3
          4
        ];
        expected = 3;
      };
      test-findFirst-default = {
        expr = p.findFirst (x: x > 9) (-1) [
          1
          2
          3
        ];
        expected = -1;
      };

      # iterateBounded: the bound's LENGTH is the iteration count and its elements are
      # never read — the next case makes every element a `throw` to say so.
      test-iterateBounded-counts = {
        expr = p.iterateBounded (_: null) (st: st + 1) 0 [
          "a"
          "b"
          "c"
        ];
        expected = 3;
      };
      test-iterateBounded-ignores-elements = {
        expr = p.iterateBounded (_: null) (st: st + 1) 0 [
          (throw "the bound's elements must never be forced")
          (throw "nor this one")
        ];
        expected = 2;
      };
      test-iterateBounded-empty-bound = {
        expr = p.iterateBounded (_: null) (st: st + 1) 7 [ ];
        expected = 7;
      };
      # The caller's half of the contract: a step that is the identity once no work remains
      # reaches the same fixed point a recursion would, and every surplus step idles.
      test-iterateBounded-surplus-steps-idle = {
        expr = p.iterateBounded (_: null) (st: if st >= 3 then st else st + 1) 0 (p.range 1 100);
        expected = 3;
      };
      # `strict` is applied to every intermediate state and FORCED. The subject forces a
      # field that throws; the control is the same loop with nothing forced, which returns
      # because `foldl'` reaches only the record and not its fields.
      test-iterateBounded-forces-carried = {
        expr = ranOverBoom (st: st.boom);
        expected = false;
      };
      test-iterateBounded-forces-carried-control = {
        expr = ranOverBoom (_: null);
        expected = true;
      };
      # Stack safety, the property the encoding exists for: 20000 iterations is twice the
      # default `max-call-depth`, where a self-applying loop spends one frame per iteration.
      # The failing arm is a SHELL arm and cannot live here — a stack overflow is an
      # uncatchable abort, so no in-language assertion observes it.
      test-iterateBounded-stack-safe = {
        expr = p.iterateBounded (_: null) (st: st + 1) 0 (p.range 1 20000);
        expected = 20000;
      };
      # The EXCEPTION to `strict`: a loop-carried field it never names is still safe when the
      # step's own guard reads it. WHNF on the state reaches the record and not `c`, but the
      # guard forces `c` before either branch is chosen, so the previous iteration's thunk
      # collapses every step and the chain stays one deep instead of growing to N. It is the
      # guard's DOMINATION of every path that builds the next state that carries this, not
      # anything about the field. The unguarded twin — the same loop with the guard deleted —
      # is the counterexample and cannot live here: it dies on the C stack when `c` is finally
      # forced, an abort `tryEval` does not contain, so it is a SHELL arm in the trap table.
      test-iterateBounded-step-guard-forces-carried = {
        expr =
          (p.iterateBounded (_: null) (st: if st.c >= 0 then { c = st.c + 1; } else st) { c = 0; } (
            p.range 1 100000
          )).c;
        expected = 100000;
      };
    };

    # Fidelity: prelude.<f> == nixpkgs lib.<f> for every vendored utility.
    prelude-fidelity = {
      test-genAttrs = {
        expr = p.genAttrs [ "a" "b" ] toString;
        expected = lib.genAttrs [ "a" "b" ] toString;
      };
      test-genAttrs-empty = {
        expr = p.genAttrs [ ] toString;
        expected = lib.genAttrs [ ] toString;
      };
      test-nameValuePair = {
        expr = p.nameValuePair "k" 1;
        expected = lib.nameValuePair "k" 1;
      };
      test-concatMap = {
        expr = p.concatMap (x: [
          x
          x
        ]) xs;
        expected = lib.concatMap (x: [
          x
          x
        ]) xs;
      };
      test-concatMap-empty = {
        expr = p.concatMap (x: [ x ]) [ ];
        expected = lib.concatMap (x: [ x ]) [ ];
      };
      test-optional-true = {
        expr = p.optional true 1;
        expected = lib.optional true 1;
      };
      test-optional-false = {
        expr = p.optional false 1;
        expected = lib.optional false 1;
      };
      test-optionalAttrs-true = {
        expr = p.optionalAttrs true attrs;
        expected = lib.optionalAttrs true attrs;
      };
      test-optionalAttrs-false = {
        expr = p.optionalAttrs false attrs;
        expected = lib.optionalAttrs false attrs;
      };
      test-optionalString-true = {
        expr = p.optionalString true "x";
        expected = lib.optionalString true "x";
      };
      test-optionalString-false = {
        expr = p.optionalString false "x";
        expected = lib.optionalString false "x";
      };
      test-last = {
        expr = p.last xs;
        expected = lib.last xs;
      };
      test-init = {
        expr = p.init xs;
        expected = lib.init xs;
      };
      test-unique = {
        expr = p.unique xs;
        expected = lib.unique xs;
      };
      test-unique-empty = {
        expr = p.unique [ ];
        expected = lib.unique [ ];
      };
      # The case above routes to the retained fold (`xs` is integers), so on its own it leaves the
      # STRING path — the one this library reimplemented — with no nixpkgs oracle at all. These
      # put it under the same assertion, which is the whole warrant for first-occurrence order.
      test-unique-strings = {
        expr = p.unique [
          "c"
          "a"
          "b"
          "a"
          "c"
          "c"
          "d"
          "b"
        ];
        expected = lib.unique [
          "c"
          "a"
          "b"
          "a"
          "c"
          "c"
          "d"
          "b"
        ];
      };
      test-unique-strings-descending = {
        expr = p.unique [
          "z"
          "y"
          "x"
          "w"
          "z"
          "a"
        ];
        expected = lib.unique [
          "z"
          "y"
          "x"
          "w"
          "z"
          "a"
        ];
      };
      test-unique-strings-all-duplicates = {
        expr = p.unique [
          "x"
          "x"
          "x"
        ];
        expected = lib.unique [
          "x"
          "x"
          "x"
        ];
      };
      test-unique-singleton = {
        expr = p.unique [ "q" ];
        expected = lib.unique [ "q" ];
      };
      # The domain nixpkgs `lib.unique` also accepts, and which the retained fold is what keeps
      # reachable: lists, attrsets, and a mixed list that must route whole rather than per element.
      test-unique-lists = {
        expr = p.unique [
          [ 1 ]
          [ 1 ]
          [ 2 ]
        ];
        expected = lib.unique [
          [ 1 ]
          [ 1 ]
          [ 2 ]
        ];
      };
      test-unique-attrs = {
        expr = p.unique [
          { a = 1; }
          { a = 1; }
          { b = 2; }
        ];
        expected = lib.unique [
          { a = 1; }
          { a = 1; }
          { b = 2; }
        ];
      };
      test-unique-mixed = {
        expr = p.unique [
          "a"
          1
          "a"
          1
        ];
        expected = lib.unique [
          "a"
          1
          "a"
          1
        ];
      };
      test-unique-attrs24 = {
        expr = p.unique strictnessClasses.attrs24;
        expected = lib.unique strictnessClasses.attrs24;
      };
      # Strictness is a fidelity property too, and no `==` comparison above can see it: both sides
      # of an equality are forced. nixpkgs `lib.unique` returns 1 here, so the length guard is
      # what keeps this assertion true rather than an extra the vendored copy added.
      test-unique-strictness-vs-nixpkgs = {
        expr = builtins.mapAttrs (_: forces p.unique) strictnessClasses;
        expected = builtins.mapAttrs (_: forces lib.unique) strictnessClasses;
      };
      test-filterAttrs = {
        expr = p.filterAttrs gt1 attrs;
        expected = lib.filterAttrs gt1 attrs;
      };
      test-mapAttrsToList = {
        expr = p.mapAttrsToList showKV attrs;
        expected = lib.mapAttrsToList showKV attrs;
      };
      test-concatMapStringsSep = {
        expr = p.concatMapStringsSep "," toString xs;
        expected = lib.concatMapStringsSep "," toString xs;
      };
      test-concatMapStringsSep-empty = {
        expr = p.concatMapStringsSep "," toString [ ];
        expected = lib.concatMapStringsSep "," toString [ ];
      };
      test-hasPrefix-match = {
        expr = p.hasPrefix "ab" "abc";
        expected = lib.hasPrefix "ab" "abc";
      };
      test-hasPrefix-nomatch = {
        expr = p.hasPrefix "xy" "abc";
        expected = lib.hasPrefix "xy" "abc";
      };
      test-hasInfix-match = {
        expr = p.hasInfix "bc" "abcd";
        expected = lib.hasInfix "bc" "abcd";
      };
      test-hasInfix-nomatch = {
        expr = p.hasInfix "xy" "abcd";
        expected = lib.hasInfix "xy" "abcd";
      };
      # Regex metacharacters in the needle must be treated literally (the purity
      # scan looks for tokens like `lib.types` and `{ lib,`).
      test-hasInfix-metachars = {
        expr = p.hasInfix "lib.types" "x = lib.types.str;";
        expected = lib.hasInfix "lib.types" "x = lib.types.str;";
      };
      test-hasInfix-metachars-nomatch = {
        expr = p.hasInfix "a.c" "abc";
        expected = lib.hasInfix "a.c" "abc";
      };
      test-escapeRegex = {
        expr = p.escapeRegex "a.b*c{d,e}";
        expected = lib.escapeRegex "a.b*c{d,e}";
      };

      # ── the metacharacter set, member by member ──
      #
      # `hasInfix` is a literal substring test built on a regex primitive, so the needle's
      # metacharacters are quoted before the engine sees them, and the quoting is correct only
      # if the set is the engine's set EXACTLY. Both directions of error can be silent, so both
      # are covered.
      #
      # DROPPING a member stops it being quoted and the needle becomes a pattern. Measured over
      # the twelve, one drop at a time: eight flip the boolean and four leave a pattern the
      # engine rejects. Which member is missing decides which needle notices, so a table of
      # representative cases cannot see this and the coverage has to be per member. Each cell's
      # comment states what its needle would MEAN unescaped — that is what makes the pair
      # discriminate rather than sample.
      #
      # ADDING a member emits `\c` for a `c` the grammar defines no escape for, and that cannot
      # be asserted the same way. For `]` the engine rejects `\]` outright, and the abort is one
      # `builtins.tryEval` does not catch — so no cell can state it as an EXPECTATION and pass;
      # a `hasInfix` cell can only fail, and how it fails is the runner's business rather than
      # the assertion's (measured with `]` planted back into the set: `nix-unit` reports the
      # three `]` arms below as ☢️ evaluation errors, and the `checks.default` asserter aborts
      # the build). `test-escapeRegex-printable-ascii` is what makes the added member an
      # ORDINARY red with a readable diff: it compares escaped output and never reaches the
      # engine.

      # `\` unescaped leaves a lone backslash as the whole pattern: not a valid regex.
      test-escset-backslash = escCell "\\" "a\\b" true;

      # `[` unescaped opens a bracket expression that nothing closes.
      test-escset-open-bracket = escCell "[a" "x[ay" true;

      # `{` unescaped makes `a{2}` an interval — "two a's" — which "ba{2}c" does not contain.
      # This is the silent one: a wrong boolean, no error.
      test-escset-open-brace = escCell "a{2}" "ba{2}c" true;

      # `(` unescaped opens a group whose closing paren is escaped: unbalanced.
      test-escset-open-paren = escCell "(a" "f(a)" true;

      # `)` unescaped closes a group that was never opened.
      test-escset-close-paren = escCell "a)" "f(a)" true;

      # `^` unescaped anchors at the start, so it matches "ab" where the literal "^a" does not
      # occur.
      test-escset-caret = escCell "^a" "ab" false;

      # `$` unescaped anchors at the end, so it matches "ba" where the literal "a$" does not
      # occur.
      test-escset-dollar = escCell "a$" "ba" false;

      # `?` unescaped makes the preceding character optional, so `ba?` matches a bare "b".
      test-escset-question = escCell "ba?" "b" false;

      # `*` unescaped makes the preceding character repeatable-from-zero, so `ba*` matches "b".
      test-escset-star = escCell "ba*" "b" false;

      # `+` unescaped makes the preceding character repeatable-from-one, so `ba+` matches "ba".
      test-escset-plus = escCell "ba+" "ba" false;

      # `.` unescaped matches any character, so `a.c` matches "abc".
      test-escset-dot = escCell "a.c" "abc" false;

      # `|` unescaped makes the needle an alternation, so `a|b` matches a bare "a".
      test-escset-pipe = escCell "a|b" "a" false;

      # ── `]` is a NON-member, and that is the load-bearing part ──
      #
      # A lone `]` is already literal to the engine — a bracket expression is only open after
      # an unescaped `[` — so quoting it is not merely unnecessary, it is wrong: `\]` is not a
      # defined escape and the engine rejects the pattern. nixpkgs leaves `]` out for that
      # reason, and these arms hold this copy to the same non-membership from both sides: the
      # escaped form, and the boolean the engine then produces.

      test-escapeRegex-close-bracket = {
        expr = p.escapeRegex "]";
        expected = lib.escapeRegex "]";
      };

      # `[` escaped and `]` not is the asymmetry stated as behaviour: `\[x]` is a valid pattern
      # matching the three literal characters.
      test-escapeRegex-bracket-expression = {
        expr = p.escapeRegex "[x]";
        expected = lib.escapeRegex "[x]";
      };

      test-hasInfix-close-bracket-match = escCell "]" "a]b" true;
      test-hasInfix-close-bracket-nomatch = escCell "]" "axb" false;
      test-hasInfix-bracket-expression = escCell "[x]" "y[x]z" true;

      # ── the set as a whole ──
      #
      # Total over single printable-ASCII characters, so it fails on any member added or
      # dropped without needing a case for that member. This is the only arm that sees an
      # ADDED member, per the note above.
      test-escapeRegex-printable-ascii = {
        expr = p.escapeRegex printableAscii;
        expected = lib.escapeRegex printableAscii;
      };
      test-imap0 = {
        expr = p.imap0 idxShow xs;
        expected = lib.imap0 idxShow xs;
      };
      test-fix = {
        expr = p.fix (self: {
          a = 1;
          b = self.a + 1;
        });
        expected = lib.fix (self: {
          a = 1;
          b = self.a + 1;
        });
      };
      test-max = {
        expr = p.max 3 7;
        expected = lib.max 3 7;
      };
      test-max-reversed = {
        expr = p.max 7 3;
        expected = lib.max 7 3;
      };
      test-range = {
        expr = p.range 1 4;
        expected = lib.range 1 4;
      };
      test-range-empty = {
        expr = p.range 4 1;
        expected = lib.range 4 1;
      };
      test-removePrefix-match = {
        expr = p.removePrefix "ab" "abcd";
        expected = lib.removePrefix "ab" "abcd";
      };
      test-removePrefix-nomatch = {
        expr = p.removePrefix "xy" "abcd";
        expected = lib.removePrefix "xy" "abcd";
      };

      # toposort has NO fidelity arm because it is no longer here. Five cases stood in
      # this section — `test-toposort-{chain,dag,single,empty,cycle}` — and every one of
      # them asserted byte-equality with nixpkgs `lib.toposort`, which is the whole reason
      # the function was vendored verbatim. Retiring the copy retires the claim: there is
      # no second implementation left for fidelity to compare. Replacements in gen-graph's
      # `order-front-door` suite carry the ORDERING and CYCLE-REPORTING behaviour forward
      # (`test-topo-chain`, `test-topo-dag`, `test-topo-single`, `test-topo-empty`,
      # `test-topo-cycle-members`) — but NOT byte-compatibility with nixpkgs, and not the
      # polymorphism that let the vendored copy sort integers and records directly. Those
      # two guarantees are deleted, not relocated; gen-graph's door reaches integer and
      # record nodes only through an explicit `keyOf` projection.

      # groupBy has NO fidelity arm, by the same rule that gives `map` and `filter` none: it is a
      # builtins alias, not a vendored utility, so there is no second implementation for fidelity to
      # compare. Retired rather than left in place because nixpkgs `lib/lists.nix` defines
      # `groupBy = builtins.groupBy or (…)` and this Nix has the primop — so `expected = lib.groupBy …`
      # against a delegating `p.groupBy` compares the primop with itself and cannot fail. A check that
      # cannot fail must not be counted as coverage. groupBy's behaviour is pinned instead by the
      # literal-expectation tests in the `prelude` suite above (partition, the empty case, and
      # within-group collision order), each verified to fail under a broken groupBy.

      # findFirst — behavior-identical to nixpkgs lib.findFirst (top-level).
      test-findFirst-match = {
        expr = p.findFirst (x: x > 1) 0 xs;
        expected = lib.findFirst (x: x > 1) 0 xs;
      };
      test-findFirst-nomatch = {
        expr = p.findFirst (x: x > 9) (-1) xs;
        expected = lib.findFirst (x: x > 9) (-1) xs;
      };
      test-findFirst-empty = {
        expr = p.findFirst (x: true) 0 [ ];
        expected = lib.findFirst (x: true) 0 [ ];
      };
      # indexOf — cross-checked against lib.lists.findFirstIndex (present in the pinned
      # nixpkgs, lib/lists.nix:575; NOT top-level lib.findFirstIndex, which does not resolve).
      test-indexOf-fidelity = {
        expr = p.indexOf xs 2;
        expected = lib.lists.findFirstIndex (y: y == 2) (-1) xs;
      };
      test-indexOf-absent-fidelity = {
        expr = p.indexOf xs 99;
        expected = lib.lists.findFirstIndex (y: y == 99) (-1) xs;
      };
    };
  };
}
