# THE DOOR CONSTRUCTS — `checkOptions`, `checkRequired`, `resolve` (den-hoag-7gp66 P1).
#
# `tests` pins what each construct ANSWERS and that every refusal is CATCHABLE (ADR-0025 item 1);
# `testsError` pins which refusal fired and that it names the door first (R6). Each refusal cell
# sits beside an admission cell on the same fixture, so an implementation that refuses everything
# reds the admissions and one that admits everything reds the refusals.
#
# The resolver's verdict is the MEMBER's. The fixture supplies gen-schema's (den-hoag-a4158 arm
# (d)): the stamp and every identity-key value equal the candidate's. The cells below pin the
# skeleton around it: the hint locates and never decides, the entry is the answer, and the index
# forces no field but the hint.
{ genPrelude, ... }:
let
  inherit (genPrelude) checkOptions checkRequired resolve;
  refused = v: !(builtins.tryEval (builtins.deepSeq v v)).success;

  entries = {
    igloo = {
      name = "igloo";
      addr = "10.0.0.1";
      note = "n";
      id_hash = "host:1";
      _identityKeys = [ "addr" ];
    };
    # A member whose `name` is not its identifier: the hint misses and the index answers.
    yurt = {
      name = "renamed";
      addr = "10.0.0.2";
      note = "n";
      id_hash = "host:2";
      _identityKeys = [ "addr" ];
    };
  };
  isCanonical =
    entries: v: k:
    let
      c = entries.${k};
    in
    (v.id_hash or null) == c.id_hash && builtins.all (f: v ? ${f} && v.${f} == c.${f}) c._identityKeys;
  hosts = resolve {
    inherit entries;
    isCanonical = isCanonical entries;
  };
  r = hosts "gen-probe.door";

  # An entry whose identity key is computed THROUGH the resolver of its own registry, from a
  # declaration whose hint MISSES. The index forces every entry's `name` and nothing else, so
  # `cabin`'s own `addr` is not dragged in.
  cyclic =
    let
      es = entries // {
        cabin = {
          name = "cabin";
          addr = es.${rc entries.yurt}.addr + "-c";
          id_hash = "host:3";
          _identityKeys = [ "addr" ];
        };
      };
      rc = resolve {
        entries = es;
        isCanonical = isCanonical es;
      } "gen-probe.door";
    in
    es.cabin.addr;
in
{
  flake.tests.door-options = {
    test-accepted-options-pass-through-unchanged = {
      expr = checkOptions "gen-probe.door" [ "a" "b" ] { a = 1; };
      expected = {
        a = 1;
      };
    };
    test-empty-options-pass = {
      expr = checkOptions "gen-probe.door" [ "a" ] { };
      expected = { };
    };
    test-unknown-option-refused-catchably = {
      expr = refused (checkOptions "gen-probe.door" [ "a" ] { colr = 1; });
      expected = true;
    };
    test-non-set-options-refused-catchably = {
      expr = refused (checkOptions "gen-probe.door" [ "a" ] [ "a" ]);
      expected = true;
    };
  };

  flake.tests.door-record = {
    # R5's stated price: a data record is open, so an extra field is admitted and never reported.
    test-extra-field-on-a-record-is-admitted = {
      expr = checkRequired "gen-probe.door" [ "a" ] {
        a = 1;
        colr = 2;
      };
      expected = {
        a = 1;
        colr = 2;
      };
    };
    test-missing-required-field-refused-catchably = {
      expr = refused (checkRequired "gen-probe.door" [ "a" "b" ] { a = 1; });
      expected = true;
    };
    test-non-set-record-refused-catchably = {
      expr = refused (checkRequired "gen-probe.door" [ "a" ] null);
      expected = true;
    };
    # A mixed door: required fields checked open, then the whole set closed.
    test-mixed-door-composes = {
      expr = refused (
        checkOptions "gen-probe.door" [ "a" "b" ] (
          checkRequired "gen-probe.door" [ "a" ] {
            a = 1;
            colr = 1;
          }
        )
      );
      expected = true;
    };
  };

  flake.tests.door-resolve = {
    test-identifier-resolves-to-itself = {
      expr = r "igloo";
      expected = "igloo";
    };
    test-unknown-identifier-refused-catchably = {
      expr = refused (r "nope");
      expected = true;
    };
    # den-hoag-3w9e7 arm (a): an identifier is a string, so an int is the wrong form.
    test-int-identifier-refused-catchably = {
      expr = refused (r 1);
      expected = true;
    };
    test-lambda-refused-catchably = {
      expr = refused (r (x: x));
      expected = true;
    };
    test-member-resolves-to-its-identifier = {
      expr = r entries.igloo;
      expected = "igloo";
    };
    test-renamed-member-resolves-through-the-index = {
      expr = r entries.yurt;
      expected = "yurt";
    };
    # A field outside the identity keys does not move the member: the value resolves to the entry,
    # and the door serves the entry rather than the value it was handed.
    test-non-key-edit-resolves-to-the-entry = {
      expr = entries.${r (entries.igloo // { note = "x"; })}.note;
      expected = "n";
    };
    test-key-edit-refused-catchably = {
      expr = refused (r (entries.igloo // { addr = "evil"; }));
      expected = true;
    };
    # The hint locates and never decides: renaming a member to another's name is refused.
    test-hint-is-not-a-verdict = {
      expr = refused (r (entries.igloo // { name = "renamed"; }));
      expected = true;
    };
    test-forged-name-refused-catchably = {
      expr = refused (r {
        name = "igloo";
        addr = "10.9.9.9";
        id_hash = "host:1";
      });
      expected = true;
    };
    test-hintless-declaration-refused-catchably = {
      expr = refused (r {
        addr = "10.0.0.1";
      });
      expected = true;
    };
    test-cyclic-registry-evaluates = {
      expr = cyclic;
      expected = "10.0.0.2-c";
    };
    # A custom locator field.
    test-hint-field-is-the-callers = {
      expr = resolve {
        entries.a = {
          label = "a";
        };
        isCanonical = v: k: v.label == k;
        hint = "label";
      } "gen-probe.door" { label = "a"; };
      expected = "a";
    };
  };

  # Every refusal names the door first and the construct last (R6).
  flake.testsError.door-refusals =
    let
      pin = msg: {
        type = "ThrownError";
        msg = "^gen-probe[.]door: ${msg}$";
      };
    in
    {
      test-unknown-option-names-field-and-accepted-set = {
        expr = checkOptions "gen-probe.door" [ "a" "b" ] {
          a = 1;
          colr = 1;
        };
        expectedError = pin "'colr' is not an option of this door; the options are closed [(]accepted: 'a', 'b'[)] [(]in prelude[.]checkOptions[)]";
      };
      test-non-set-options-named = {
        expr = checkOptions "gen-probe.door" [ "a" ] 3;
        expectedError = pin "the options must be an attrset, not a int [(]accepted: 'a'[)] [(]in prelude[.]checkOptions[)]";
      };
      test-missing-field-named = {
        expr = checkRequired "gen-probe.door" [ "a" "b" ] { a = 1; };
        expectedError = pin "required field 'b' is missing [(]required: 'a', 'b'[)] [(]in prelude[.]checkRequired[)]";
      };
      test-non-set-record-named = {
        expr = checkRequired "gen-probe.door" [ "a" ] null;
        expectedError = pin "the argument must be an attrset, not a null [(]required: 'a'[)] [(]in prelude[.]checkRequired[)]";
      };
      test-unknown-identifier-named = {
        expr = r "nope";
        expectedError = pin "reference 'nope' names no entry of the registry [(]in prelude[.]resolve[)]";
      };
      test-wrong-form-named = {
        expr = r 1;
        expectedError = pin "expected an identifier [(]a string[)] or a declaration [(]an attrset[)], got a int [(]in prelude[.]resolve[)]";
      };
      test-hintless-declaration-named = {
        expr = r { addr = "10.0.0.1"; };
        expectedError = pin "a declaration must carry a string 'name' to locate it [(]expected an attrset[)] [(]in prelude[.]resolve[)]";
      };
      test-non-member-named = {
        expr = r (entries.igloo // { addr = "evil"; });
        expectedError = pin "declaration 'igloo' is not a member of the registry [(]available: 'igloo', 'yurt'[)] [(]in prelude[.]resolve[)]";
      };
      test-renamed-non-member-named = {
        expr = r (entries.yurt // { addr = "evil"; });
        expectedError = pin "declaration 'renamed' is not a member of the registry [(]available: 'igloo', 'yurt'[)] [(]in prelude[.]resolve[)]";
      };
    };
}
