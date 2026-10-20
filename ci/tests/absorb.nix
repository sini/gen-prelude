# `absorb` (den-hoag-kunjm's quotient rule; its home here is den-hoag-izo7a): a kept datum carries
# the union of its `==` twins' store-context edges, and a collapse that would lose one is refused
# under the CALLER's door name, verbatim. `tests` holds the values, `testsError` each refusal's text.
# Every context below is a `toFile` store path, so each count is the number of distinct paths.
{ genPrelude, ... }:
let
  inherit (genPrelude) absorb;
  site = {
    fn = "gen-x.door";
    subject = "the collapse";
    at = " at 'k'";
  };
  a = builtins.toFile "absorb-ctx-a" "a";
  b = builtins.toFile "absorb-ctx-b" "b";
  bareA = builtins.unsafeDiscardStringContext a;
  # Two strings `==`-equal (both empty) carrying different contexts.
  ca = builtins.substring 0 0 a;
  cb = builtins.substring 0 0 b;
  ctx = s: builtins.length (builtins.attrNames (builtins.getContext s));
  refusal = msg: {
    type = "ThrownError";
    msg = "^gen-x[.]door: the collapse collapses ${msg}$";
  };
in
{
  flake.tests.absorb = {
    test-no-twins-returns-kept-unforced = {
      expr = builtins.isNull (absorb site null [ ]);
      expected = true;
    };
    test-string-kept-carries-the-union = {
      expr = ctx (absorb site ca [ cb ]);
      expected = 2;
    };
    # The control on the count: the kept string alone carries one.
    test-control-string-kept-alone-carries-one = {
      expr = ctx ca;
      expected = 1;
    };
    test-context-free-twins-leave-a-non-string-kept-as-is = {
      expr = absorb site [ "x" ] [ [ "x" ] ];
      expected = [ "x" ];
    };
    test-a-non-string-kept-already-carrying-the-edge-is-admitted = {
      expr = absorb site [ a ] [ [ bareA ] ];
      expected = [ a ];
    };
    test-a-derivation-is-read-by-its-outPath = {
      expr =
        let
          drv = {
            type = "derivation";
            outPath = a;
          };
        in
        absorb site drv [ { inherit (drv) type outPath; } ];
      expected = {
        type = "derivation";
        outPath = a;
      };
    };
  };

  flake.testsError.absorb = {
    test-a-non-string-collapse-losing-an-edge-is-refused-under-the-callers-door = {
      expr = absorb site [ bareA ] [ [ a ] ];
      expectedError = refusal "a non-string datum at 'k' with 1 `==`-equal twin[(]s[)] whose store dependencies it does not carry [(].*-absorb-ctx-a[)]; a collapse keeps its twins' dependency edges, and only a string can carry the union";
    };
    test-an-uncertified-kept-is-refused-by-shape = {
      expr =
        absorb site
          {
            outPath = "o";
            extra = a;
          }
          [
            {
              outPath = "o";
              extra = a;
            }
          ];
      expectedError = refusal "a datum at 'k' holding a coercible set that is not a derivation and has attributes besides its coercion; a store dependency there is an edge the collapse cannot read, so it cannot carry it";
    };
  };
}
