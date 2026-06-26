{ genPrelude, ... }:
{
  flake.tests.prelude = {
    test-genAttrs = {
      expr = genPrelude.genAttrs [ "a" "b" ] (n: n + "!");
      expected = {
        a = "a!";
        b = "b!";
      };
    };
    test-optional-true = {
      expr = genPrelude.optional true 1;
      expected = [ 1 ];
    };
    test-optional-false = {
      expr = genPrelude.optional false 1;
      expected = [ ];
    };
    test-unique = {
      expr = genPrelude.unique [
        1
        1
        2
        3
        3
        2
      ];
      expected = [
        1
        2
        3
      ];
    };
    test-last = {
      expr = genPrelude.last [
        1
        2
        3
      ];
      expected = 3;
    };
    test-filterAttrs = {
      expr = genPrelude.filterAttrs (_n: v: v > 1) {
        a = 1;
        b = 2;
        c = 3;
      };
      expected = {
        b = 2;
        c = 3;
      };
    };
    test-concatMapStringsSep = {
      expr = genPrelude.concatMapStringsSep "," (x: x) [
        "a"
        "b"
        "c"
      ];
      expected = "a,b,c";
    };
    test-hasPrefix = {
      expr = genPrelude.hasPrefix "ab" "abc";
      expected = true;
    };
  };
}
