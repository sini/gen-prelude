# NESTED PER-STEP CONTRACTS — `door`'s `next` (den-hoag-ak8va; OQ16 "nest", owner 2026-09-28).
#
# A chained door publishes its next step's contract AS DATA, `__contract.next`, from a spec bound
# once and used both as `next` and in the body's `door`. At application the door refuses, by name,
# a body whose result is not a door named `next.name` (the drift guard). Refusal cells force the
# WHNF of the application only, as door-constructor.nix's do.
{ genPrelude, ... }:
let
  inherit (genPrelude) door;
  refusedAtApplication = e: !(builtins.tryEval (builtins.seq e null)).success;
  refusedAtSpec = e: !(builtins.tryEval (builtins.seq e null)).success;

  # N1: the ruled form — the record step's spec bound once, used as `next` and as the step.
  recordSpec = {
    name = "gen-probe.nest";
    required = [ "parent" ];
    open = true;
    optionsStep = nested; # the OUTER door: `contractOf` must never read it (the cycle)
  };
  record = door recordSpec;
  nested = door {
    name = "gen-probe.nest";
    optional = [ "maxDepth" ];
    next = recordSpec;
  } (o: record (r: id: [ id ]));

  # N2: a declared next the body does not return (a different door; a non-door).
  otherDoor = door {
    name = "gen-probe.other";
    required = [ "x" ];
  } (r: r);
  drifted = door {
    name = "gen-probe.drift";
    optional = [ "maxDepth" ];
    next = recordSpec;
  } (o: otherDoor);
  notADoor = door {
    name = "gen-probe.drift";
    optional = [ "maxDepth" ];
    next = recordSpec;
  } (o: id: id);

  # N3: three steps — `next.next`.
  thirdSpec = {
    name = "gen-probe.three";
    required = [ "leaf" ];
    open = true;
  };
  secondSpec = {
    name = "gen-probe.three";
    required = [ "mid" ];
    open = true;
    next = thirdSpec;
  };
  three =
    door
      {
        name = "gen-probe.three";
        optional = [ "o" ];
        next = secondSpec;
      }
      (
        o:
        door secondSpec (
          m:
          door thirdSpec (l: [
            o
            m
            l
          ])
        )
      );

  # The anchor (OQ-2): a record step naming its `optionsStep` must be that door's declared `next`.
  # An undeclared chain, and a same-name drift (gate C1's mutant: the family's name, a false field).
  undeclaredSpec = {
    name = "gen-probe.undeclared";
    required = [ "parent" ];
    open = true;
    optionsStep = undeclared;
  };
  undeclared = door {
    name = "gen-probe.undeclared";
    optional = [ "maxDepth" ];
  } (o: door undeclaredSpec (r: r));
  sameNameSpec = {
    name = "gen-probe.samename";
    required = [ "edges" ];
    open = true;
    optionsStep = sameName;
  };
  sameName = door {
    name = "gen-probe.samename";
    optional = [ "maxDepth" ];
    next = sameNameSpec // {
      required = [ "parent" ];
    };
  } (o: door sameNameSpec (r: r));

  # A positional node (OQ-1 arm (a)): options -> `engine` (a plain lambda) -> record.
  positionalRecordSpec = {
    name = "gen-probe.positional";
    required = [ "nodes" ];
    open = true;
    optionsStep = positional;
  };
  positionalRecord = door positionalRecordSpec;
  positional = door {
    name = "gen-probe.positional";
    optional = [ "o" ];
    next = {
      positional = "engine";
      next = positionalRecordSpec;
    };
  } (o: engine: positionalRecord (r: engine r.nodes));
  positionalDrift = door {
    name = "gen-probe.positionalDrift";
    next = {
      positional = "engine";
      next = thirdSpec;
    };
  } (o: { });
in
{
  flake.tests.door-next = {
    test-control-seq-catches-a-throw = {
      expr = refusedAtApplication (throw "control probe");
      expected = true;
    };

    # N1: the next step's contract is published as data, and the first step's map is unchanged.
    test-N1-next-contract-published = {
      expr = nested.__contract.next;
      expected = {
        name = "gen-probe.nest";
        required = [ "parent" ];
        optional = [ ];
        open = true;
      };
    };
    test-N1-function-args-read-the-first-step-only = {
      expr = nested.__functionArgs;
      expected = {
        maxDepth = true;
      };
    };
    test-N1-chain-answers = {
      expr = nested { maxDepth = 1; } { parent = null; } "a";
      expected = [ "a" ];
    };
    test-N1-chain-answers-through-the-empty-options-fast-path = {
      expr = nested { } { parent = null; } "a";
      expected = [ "a" ];
    };
    test-N1-step-two-still-refuses-a-missing-field = {
      expr = refusedAtApplication (nested { } { });
      expected = true;
    };
    test-N1-step-two-still-refuses-a-misplaced-option = {
      expr = refusedAtApplication (
        nested { } {
          parent = null;
          maxDepth = 2;
        }
      );
      expected = true;
    };
    test-N1-a-door-without-next-publishes-no-next = {
      expr = (record (r: r)).__contract ? next;
      expected = false;
    };

    # N2: the drift guard, both shapes, catchable.
    test-N2-a-different-door-is-refused-at-application = {
      expr = refusedAtApplication (drifted { });
      expected = true;
    };
    test-N2-a-different-door-is-refused-with-options-given = {
      expr = (builtins.tryEval (builtins.seq (drifted { maxDepth = 1; }) null)).success;
      expected = false;
    };
    test-N2-a-non-door-is-refused-at-application = {
      expr = refusedAtApplication (notADoor { });
      expected = true;
    };

    # N3: a three-step chain is `next.next`.
    test-N3-next-next = {
      expr = three.__contract.next.next.required;
      expected = [ "leaf" ];
    };
    test-N3-three-steps-answer = {
      expr = three { o = 1; } { mid = 2; } { leaf = 3; };
      expected = [
        { o = 1; }
        { mid = 2; }
        { leaf = 3; }
      ];
    };

    # N4: the `next` spec is checked at `door spec`, like the door's own.
    test-N4-next-spec-typo-refused = {
      expr = refusedAtSpec (door {
        name = "gen-probe.bad";
        next = {
          name = "gen-probe.bad";
          requried = [ "x" ];
        };
      });
      expected = true;
    };
    test-N4-next-spec-without-name-refused = {
      expr = refusedAtSpec (door {
        name = "gen-probe.bad";
        next = {
          required = [ "x" ];
        };
      });
      expected = true;
    };
    test-N4-next-spec-overlap-refused = {
      expr = refusedAtSpec (door {
        name = "gen-probe.bad";
        next = {
          name = "gen-probe.bad";
          required = [ "x" ];
          optional = [ "x" ];
        };
      });
      expected = true;
    };
    test-N4-nested-next-spec-typo-refused = {
      expr = refusedAtSpec (door {
        name = "gen-probe.bad";
        next = secondSpec // {
          next = thirdSpec // {
            opne = true;
          };
        };
      });
      expected = true;
    };
    test-N4-ctl-a-good-next-spec-builds = {
      expr = refusedAtSpec (door {
        name = "gen-probe.good";
        next = secondSpec;
      });
      expected = false;
    };

    # The in-library consumer: `resolve`'s registry step is published, and the nest is the step.
    test-N5-resolve-publishes-its-registry-step = {
      expr = genPrelude.resolve.__contract.next.required;
      expected = [
        "entries"
        "isCanonical"
      ];
    };
    # PARITY (gate C1, gating): the published nest, read without application, equals the contract
    # the applied step answers with.
    test-parity-resolve = {
      expr = genPrelude.resolve.__contract.next or null == (genPrelude.resolve { }).__contract;
      expected = true;
    };
    test-parity-N1-nested = {
      expr = nested.__contract.next or null == (nested { }).__contract;
      expected = true;
    };

    # The anchor: an undeclared chain and a same-name drift are refused when the record step is
    # built, catchably; the declared chain (N1) is the control.
    test-anchor-undeclared-chain-refused = {
      expr = refusedAtApplication (undeclared { });
      expected = true;
    };
    test-anchor-same-name-drift-refused = {
      expr = refusedAtApplication (sameName { });
      expected = true;
    };
    test-anchor-ctl-declared-chain-builds = {
      expr = refusedAtApplication (nested { });
      expected = false;
    };

    # Positional nodes: published as data, the chain answers, and the record step anchors past it.
    test-positional-contract-published = {
      expr = positional.__contract.next;
      expected = {
        positional = "engine";
        next = {
          name = "gen-probe.positional";
          required = [ "nodes" ];
          optional = [ ];
          open = true;
        };
      };
    };
    test-positional-chain-answers = {
      expr = positional { } (ns: ns ++ [ "z" ]) { nodes = [ "a" ]; };
      expected = [
        "a"
        "z"
      ];
    };
    test-parity-positional = {
      expr = positional.__contract.next.next or null == (positional { } (x: x)).__contract;
      expected = true;
    };
    test-positional-guard-refuses-a-non-function = {
      expr = refusedAtApplication (positionalDrift { });
      expected = true;
    };
    test-positional-node-typo-refused-at-spec = {
      expr = refusedAtSpec (door {
        name = "gen-probe.bad";
        next = {
          positional = "engine";
          nxt = thirdSpec;
        };
      });
      expected = true;
    };
  };

  # The new refusals, byte-pinned: the door first, the construct last (R6).
  flake.testsError.door-next-refusals =
    let
      pin = door: msg: {
        type = "ThrownError";
        msg = "^${door}: ${msg}$";
      };
    in
    {
      test-N2-drift-to-another-door-named = {
        expr = drifted { };
        expectedError = pin "gen-probe[.]drift" "the contract declares the next step 'gen-probe[.]nest', but the body returned the door 'gen-probe[.]other' [(]in prelude[.]door[)]";
      };
      test-N2-drift-to-a-non-door-named = {
        expr = notADoor { maxDepth = 1; };
        expectedError = pin "gen-probe[.]drift" "the contract declares the next step 'gen-probe[.]nest', but the body returned a lambda [(]in prelude[.]door[)]";
      };
      test-N4-next-spec-typo-named = {
        expr = door {
          name = "gen-probe.bad";
          next = {
            name = "gen-probe.bad";
            requried = [ "x" ];
          };
        } (x: x);
        expectedError = pin "gen-prelude[.]door [(]the next step of 'gen-probe[.]bad'[)]" "'requried' is not an option of this door; the options are closed [(]accepted: 'name', 'required', 'optional', 'open', 'optionsStep', 'next'[)] [(]in prelude[.]checkOptions[)]";
      };
      test-N4-next-spec-overlap-named = {
        expr = door {
          name = "gen-probe.bad";
          next = {
            name = "gen-probe.inner";
            required = [ "x" ];
            optional = [ "x" ];
          };
        } (x: x);
        expectedError = pin "gen-prelude[.]door [(]the next step of 'gen-probe[.]bad'[)]" "'x' is both required and optional in the next step 'gen-probe[.]inner' [(]in prelude[.]door[)]";
      };
      test-anchor-undeclared-chain-named = {
        expr = undeclared { };
        expectedError = pin "gen-prelude[.]door" "'gen-probe[.]undeclared' is this record step's optionsStep but declares no next step [(]in the contract of 'gen-probe[.]undeclared'[)] [(]in prelude[.]door[)]";
      };
      test-anchor-same-name-drift-named = {
        expr = sameName { };
        expectedError = pin "gen-prelude[.]door" "'gen-probe[.]samename' declares a next step that is not this record step's contract [(]in the contract of 'gen-probe[.]samename'[)] [(]in prelude[.]door[)]";
      };
      test-positional-drift-named = {
        expr = positionalDrift { };
        expectedError = pin "gen-probe[.]positionalDrift" "the contract declares the positional step 'engine', but the body returned a set [(]in prelude[.]door[)]";
      };
      test-positional-node-typo-named = {
        expr = door {
          name = "gen-probe.bad";
          next = {
            positional = "engine";
            nxt = thirdSpec;
          };
        } (x: x);
        expectedError = pin "gen-prelude[.]door [(]the next step of 'gen-probe[.]bad'[)]" "required field 'next' is missing [(]required: 'positional', 'next'[)] [(]in prelude[.]checkRequired[)]";
      };
    };
}
