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
  # toposort comparators: asc = linear order; cyc = a mutual 1↔2 cycle.
  asc = a: b: a < b;
  cyc = a: b: (a == 1 && b == 2) || (a == 2 && b == 1);
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
      # toposort (vendored verbatim): linear order sorts ascending; cycles report `cycle`.
      test-toposort-result = {
        expr =
          (p.toposort (a: b: a < b) [
            3
            1
            2
          ]).result;
        expected = [
          1
          2
          3
        ];
      };
      test-toposort-cycle-detected = {
        expr =
          (p.toposort (a: b: (a == 1 && b == 2) || (a == 2 && b == 1)) [
            1
            2
          ]) ? cycle;
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

      # toposort — vendored verbatim; must match nixpkgs' { result } | { cycle; loops }.
      # asc = "a must come before b iff a < b" (a linear partial order).
      test-toposort-chain = {
        expr = p.toposort asc [
          3
          1
          2
        ];
        expected = lib.toposort asc [
          3
          1
          2
        ];
      };
      test-toposort-dag = {
        expr = p.toposort asc [
          5
          2
          8
          1
          3
        ];
        expected = lib.toposort asc [
          5
          2
          8
          1
          3
        ];
      };
      test-toposort-single = {
        expr = p.toposort asc [ 7 ];
        expected = lib.toposort asc [ 7 ];
      };
      test-toposort-empty = {
        expr = p.toposort asc [ ];
        expected = lib.toposort asc [ ];
      };
      test-toposort-cycle = {
        expr = p.toposort cyc [
          1
          2
        ];
        expected = lib.toposort cyc [
          1
          2
        ];
      };

      test-groupBy = {
        expr = p.groupBy (n: if n > 2 then "big" else "small") xs;
        expected = lib.groupBy (n: if n > 2 then "big" else "small") xs;
      };
      test-groupBy-empty = {
        expr = p.groupBy (n: toString n) [ ];
        expected = lib.groupBy (n: toString n) [ ];
      };
      test-groupBy-collision = {
        expr = p.groupBy (s: builtins.substring 0 1 s) [
          "art"
          "ale"
          "banana"
          "arc"
        ];
        expected = lib.groupBy (s: builtins.substring 0 1 s) [
          "art"
          "ale"
          "banana"
          "arc"
        ];
      };
    };
  };
}
