# A DOOR'S RETIRED OPTIONS (den-hoag-7gp66 P2 L5, orchestrator-ruled Q1 (C)) — `door { …; retired =
# { <old> = "<its replacement>"; }; }`. The shared options check learns the grammar's migration form:
# an option the door once accepted is refused BY NAME, naming its replacement, where any other
# unknown field keeps the plain refusal. Additive: a door with no `retired` publishes the contract it
# published before, and its refusals are unchanged.
#
# Every refusal cell forces the WHNF of the application only (`seq (d args) null`), as the
# constructor's own cells do; WHICH refusal fired is pinned on the error plane below.
{ genPrelude, ... }:

let
  inherit (genPrelude) door refusals escapeRegex;
  refusedAtApplication = e: !(builtins.tryEval (builtins.seq e null)).success;

  spec = {
    name = "gen-probe.retiring";
    optional = [ "keySemantics" ];
    retired.classes = "`keySemantics`";
  };
  retiring = door spec (o: o);
  plain = door {
    name = "gen-probe.retiring";
    optional = [ "keySemantics" ];
  } (o: o);
  exactly = m: {
    type = "ThrownError";
    msg = "^" + escapeRegex m + "$";
  };
in
{
  flake.tests.door-retired = {
    test-control-an-accepted-option-passes = {
      expr = retiring { keySemantics = 1; };
      expected = {
        keySemantics = 1;
      };
    };
    test-a-retired-option-is-refused-at-the-application = {
      expr = refusedAtApplication (retiring {
        classes = { };
      });
      expected = true;
    };
    test-a-plain-unknown-option-is-still-refused = {
      expr = refusedAtApplication (retiring {
        colr = 1;
      });
      expected = true;
    };
    # The retired names are published with the contract, as data.
    test-the-contract-publishes-the-retired-options = {
      expr = retiring.__contract;
      expected = {
        name = "gen-probe.retiring";
        open = false;
        optional = [ "keySemantics" ];
        required = [ ];
        retired.classes = "`keySemantics`";
      };
    };
    # Additive: a door without `retired` publishes exactly the contract it did before.
    test-a-door-without-retired-publishes-no-retired-field = {
      expr = builtins.attrNames plain.__contract;
      expected = [
        "name"
        "open"
        "optional"
        "required"
      ];
    };
    # The spec is checked at `door spec`: a retired field still accepted, a retired set on an open
    # record (which admits every extra field), and a replacement that is not text are each refused.
    test-a-retired-field-that-is-still-accepted-is-refused-at-door-spec = {
      expr = refusedAtApplication (door (spec // { retired.keySemantics = "x"; }));
      expected = true;
    };
    test-retired-on-an-open-record-is-refused-at-door-spec = {
      expr = refusedAtApplication (door {
        name = "gen-probe.open";
        required = [ "a" ];
        open = true;
        retired.b = "`a`";
      });
      expected = true;
    };
    test-a-non-text-replacement-is-refused-at-door-spec = {
      expr = refusedAtApplication (door (spec // { retired.classes = 1; }));
      expected = true;
    };
  };

  flake.testsError.door-retired = {
    test-a-retired-option-names-its-replacement = {
      expr = retiring { classes = { }; };
      expectedError = {
        type = "ThrownError";
        msg = "^gen-probe[.]retiring: 'classes' is a retired option of this door; its replacement is `keySemantics` [(]in prelude[.]checkOptions[)]$";
      };
    };
    test-retiredOption-is-the-thrown-text = {
      expr = retiring { classes = { }; };
      expectedError = exactly (refusals.retiredOption "gen-probe.retiring" "`keySemantics`" "classes");
    };
    # A retired field is preferred over a plain unknown one in the same call: its remedy is known.
    test-a-retired-option-is-named-before-a-plain-unknown-one = {
      expr = retiring {
        aaa = 1;
        classes = { };
      };
      expectedError = exactly (refusals.retiredOption "gen-probe.retiring" "`keySemantics`" "classes");
    };
    # The plain refusal is unchanged on a retiring door.
    test-a-plain-unknown-option-keeps-its-refusal = {
      expr = retiring { colr = 1; };
      expectedError = exactly (refusals.unknownOption "gen-probe.retiring" [ "keySemantics" ] "colr");
    };
  };
}
