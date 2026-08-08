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
  showKV = n: v: "${n}=${toString v}";
  idxShow = i: x: "${toString i}:${toString x}";
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
