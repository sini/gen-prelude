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
      # toposort is a deliberate throw-stub (not yet vendored) — it must throw, not
      # poison set construction.
      test-toposort-stub-throws = {
        expr = (builtins.tryEval p.toposort).success;
        expected = false;
      };
      test-last-empty-throws = {
        expr = (builtins.tryEval (p.last [ ])).success;
        expected = false;
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
    };
  };
}
