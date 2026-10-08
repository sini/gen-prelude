# THE DOOR CONSTRUCTOR — `door` — AND THE FUNCTOR-AWARE READERS (den-hoag-7gp66 P2, den-hoag-49yxv).
#
# The P2 spec's cells D0–D5 (D4, the vocabulary walk, is the hub's). Every refusal cell forces the
# WHNF of the APPLICATION only — `seq (d args) null` — and never `deepSeq`: a `deepSeq` cell reads a
# LAZY door (`body (check args)`) as refusing, so it cannot tell that form from the strict one
# (trap 23e19dc0). The door bodies below are lazy on purpose (`a: { v = a.hostName; }`: the result's
# WHNF reads no field), so only a check forced by the door itself can refuse.
#
# D5's uncatchable arm — `builtins.functionArgs` on a door aborts past `tryEval` (`'functionArgs'
# requires a function`) — cannot be a cell: it would abort the suite it reports on. It is driven
# out-of-band in the landing report.
{ lib, genPrelude, ... }:
let
  inherit (genPrelude) door functionArgs isFunction;
  refusedAtApplication = e: !(builtins.tryEval (builtins.seq e null)).success;

  lazyBody = a: { v = a.hostName; };
  spec = {
    name = "gen-probe.door";
    required = [ "hostName" ];
    optional = [ "other" ];
  };
  closed = door spec lazyBody;
  open =
    door
      {
        name = "gen-probe.open";
        required = [ "parent" ];
        open = true;
      }
      (r: {
        v = r.parent;
      });
  options = door {
    name = "gen-probe.options";
    optional = [ "maxDepth" ];
  } (o: o);
  # A curried door is a chain: an options door returning a record-operand door returning a
  # positional step.
  record = door {
    name = "gen-probe.curried";
    required = [ "parent" ];
    open = true;
  };
  curried = door {
    name = "gen-probe.curried";
    optional = [ "maxDepth" ];
  } (o: record (r: id: [ id ]));

  # (v1.2, den-hoag-7gp66 premise 7, cells G10/G10-ctl) a chained door whose record step guards
  # against its own options step: `optionsStep` names the OUTER, already-built door
  # (`guardedOptionsStep`), even though that door's own definition calls back into
  # `guardedRecord` — the contract thunk is independent of the functor thunk.
  # The record step's spec is bound once and published as the options step's `next`
  # (den-hoag-ak8va): a record step naming its `optionsStep` is refused unless that door declares it.
  guardedRecordSpec = {
    name = "gen-probe.guarded";
    required = [ "rules" ];
    open = true;
    optionsStep = guardedOptionsStep;
  };
  guardedOptionsStep = door {
    name = "gen-probe.guarded";
    optional = [ "exclusive" ];
    next = guardedRecordSpec;
  } (o: guardedRecord o);
  guardedRecord =
    o:
    door guardedRecordSpec (r: {
      inherit o r;
    });

  derived =
    d:
    builtins.listToAttrs (map (n: lib.nameValuePair n false) d.__contract.required)
    // builtins.listToAttrs (map (n: lib.nameValuePair n true) d.__contract.optional);
  agrees = d: d.__functionArgs == derived d;
  # A hand-written functor whose published map disagrees with its check (marks the required field
  # optional): the defect `door` rules out by deriving both from one contract.
  handWritten = {
    __contract = spec;
    __functionArgs = {
      hostName = true;
      other = true;
    };
    __functor = _: closed.__functor closed;
  };
in
{
  flake.tests.door-constructor = {
    # Live control for every `refusedAtApplication` cell: the predicate catches an ordinary throw
    # and passes a value.
    test-control-seq-catches-a-throw = {
      expr = refusedAtApplication (throw "control probe");
      expected = true;
    };
    test-control-seq-passes-a-value = {
      expr = refusedAtApplication 1;
      expected = false;
    };

    # D0
    test-D0-the-constructor-is-published = {
      expr = genPrelude ? door;
      expected = true;
    };

    # D1: an unknown field is refused at the application, on a lazy body.
    test-D1-unknown-field-refused-at-application = {
      expr = refusedAtApplication (closed {
        hostName = 1;
        colr = 1;
      });
      expected = true;
    };
    # D2: a missing required field is refused at the application, on the same door.
    test-D2-missing-required-field-refused-at-application = {
      expr = refusedAtApplication (closed {
        other = 1;
      });
      expected = true;
    };
    test-D2-good-call-answers = {
      expr = (closed { hostName = 7; }).v;
      expected = 7;
    };
    test-D2-optional-field-admitted = {
      expr =
        (closed {
          hostName = 7;
          other = 1;
        }).v;
      expected = 7;
    };
    test-D2-non-set-refused-at-application = {
      expr = refusedAtApplication (closed 3);
      expected = true;
    };
    # R5: an open door admits an extra field and refuses a missing one.
    test-D2-open-door-admits-an-extra-field = {
      expr =
        (open {
          parent = 3;
          colr = 1;
        }).v;
      expected = 3;
    };
    test-D2-open-door-refuses-a-missing-field = {
      expr = refusedAtApplication (open { });
      expected = true;
    };

    # A pure options door: `{ }` answers (the fast path), and an unknown option is refused when
    # `f opts` is formed, before any later argument.
    test-options-door-empty-options-answer = {
      expr = options { };
      expected = { };
    };
    test-options-door-given-options-answer = {
      expr = options { maxDepth = 3; };
      expected = {
        maxDepth = 3;
      };
    };
    test-options-door-unknown-option-refused-at-application = {
      expr = refusedAtApplication (options {
        colr = 1;
      });
      expected = true;
    };
    test-options-door-non-set-refused-at-application = {
      expr = refusedAtApplication (options [ ]);
      expected = true;
    };
    test-curried-options-step-refused-at-application = {
      expr = refusedAtApplication (curried {
        colr = 1;
      });
      expected = true;
    };
    test-curried-record-step-refused-at-application = {
      expr = refusedAtApplication (curried { } { });
      expected = true;
    };
    test-curried-door-answers = {
      expr = curried { maxDepth = 1; } { parent = null; } "a";
      expected = [ "a" ];
    };

    # G10 (v1.2, den-hoag-7gp66 premise 7): an option of the door's own options step, given on
    # the record step instead, is refused by name rather than silently admitted and ignored.
    test-G10-misplaced-option-refused-at-record-step = {
      expr = refusedAtApplication (
        guardedOptionsStep { } {
          rules = [ ];
          exclusive = true;
        }
      );
      expected = true;
    };
    # G10-ctl: a field that is neither required nor a sibling option keeps R5's width subtyping.
    test-G10-ctl-unrelated-field-admitted-unchanged = {
      expr =
        (guardedOptionsStep { } {
          rules = [ ];
          colr = 1;
        }).r.colr;
      expected = 1;
    };
    # The sibling's own options are still checked normally through the guarded record step.
    test-G10-sibling-options-still-given-through-first-step = {
      expr = (guardedOptionsStep { exclusive = true; } { rules = [ ]; }).o.exclusive;
      expected = true;
    };
    # (v1.2) `optionsStep` without `open = true` is refused at `door spec`, before any body.
    test-optionsStep-without-open-refused-at-door-spec = {
      expr = refusedAtApplication (
        door {
          name = "gen-probe.badGuard1";
          required = [ "rules" ];
          open = false;
          optionsStep = guardedOptionsStep;
        } (r: r)
      );
      expected = true;
    };
    # (v1.2) a required field that is also one of the sibling's guarded names is refused at
    # `door spec`: self-contradictory, since a required field can never be legally omitted.
    test-optionsStep-required-overlap-refused-at-door-spec = {
      expr = refusedAtApplication (
        door {
          name = "gen-probe.badGuard2";
          required = [ "exclusive" ];
          open = true;
          optionsStep = guardedOptionsStep;
        } (r: r)
      );
      expected = true;
    };

    # D3: the published map agrees with the contract, and nixpkgs' reader reads it.
    test-D3-closed-map-agrees-with-the-contract = {
      expr = [
        (agrees closed)
        (
          closed.__functionArgs == {
            hostName = false;
            other = true;
          }
        )
        # P1 (door-fold gate): against the native-formals lambda the door stands for, not against
        # its own `__functionArgs` (`lib.functionArgs`'s definition reads that, so it cannot red).
        (
          lib.functionArgs closed == builtins.functionArgs (
            {
              hostName,
              other ? null,
            }:
            null
          )
        )
      ];
      expected = [
        true
        true
        true
      ];
    };
    test-D3-open-map-agrees-with-the-contract = {
      expr = [
        (agrees open)
        (lib.functionArgs open == builtins.functionArgs ({ parent, ... }: null))
      ];
      expected = [
        true
        true
      ];
    };
    test-D3-contract-is-published = {
      expr = closed.__contract;
      expected = spec // {
        open = false;
      };
    };
    # The agreement predicate is live: it reads a hand-written disagreeing map as disagreeing.
    test-D3-control-hand-written-map-disagrees = {
      expr = agrees handWritten;
      expected = false;
    };

    # D5: the readers on a door. The builtin is blind to a functor; the prelude's reader is
    # nixpkgs', and reads a chained door step by step.
    test-D5-builtin-isFunction-is-blind-to-a-door = {
      expr = builtins.isFunction closed;
      expected = false;
    };
    test-D5-isFunction-reads-a-door = {
      expr = [
        (isFunction closed)
        (isFunction curried)
        (isFunction (curried { }))
      ];
      expected = [
        true
        true
        true
      ];
    };
    test-D5-functionArgs-reads-a-chained-door-by-step = {
      expr = [
        (functionArgs curried)
        (functionArgs (curried { }))
      ];
      expected = [
        { maxDepth = true; }
        { parent = false; }
      ];
    };

    # The constructor is itself a door over its own spec record, and `resolve` is built from it.
    # `optionsStep` (v1.2, den-hoag-7gp66 premise 7) joined the spec's own optional field set.
    test-door-publishes-its-own-contract = {
      expr = functionArgs door;
      expected = {
        name = false;
        required = true;
        optional = true;
        open = true;
        optionsStep = true;
        next = true;
      };
    };
    test-door-refuses-a-missing-name-at-application = {
      expr = refusedAtApplication (door { });
      expected = true;
    };
    test-door-refuses-an-unknown-spec-field-at-application = {
      expr = refusedAtApplication (door {
        name = "gen-probe.door";
        requried = [ ];
      });
      expected = true;
    };
    # K2 (door-fold gate): the constructor's own spec is a closed door, checked at `door spec`.
    test-door-refuses-a-required-optional-overlap-at-application = {
      expr = refusedAtApplication (door {
        name = "gen-probe.door";
        required = [ "a" ];
        optional = [ "a" ];
      });
      expected = true;
    };
    test-door-spec-typo-refused-before-any-body = {
      expr = refusedAtApplication (door {
        name = "gen-probe.door";
        requried = [ "a" ];
      });
      expected = true;
    };
    test-resolve-publishes-both-record-steps = {
      expr = [
        (functionArgs genPrelude.resolve)
        (functionArgs (genPrelude.resolve { }))
      ];
      expected = [
        {
          hint = true;
          form = true;
        }
        {
          entries = false;
          isCanonical = false;
        }
      ];
    };
  };

  # The readers ARE nixpkgs' `lib.isFunction` / `lib.functionArgs`, over lambdas, functors with and
  # without a published map, doors and non-functions.
  flake.tests.reader-fidelity =
    let
      withMap = lib.setFunctionArgs (a: a) { x = false; };
      withoutMap = {
        __functor =
          _:
          {
            y ? 1,
          }:
          y;
      };
      values = [
        (x: x)
        (
          {
            a,
            b ? 1,
          }:
          a
        )
        withMap
        withoutMap
        closed
        curried
      ];
    in
    {
      test-isFunction-fidelity = {
        expr = map isFunction (
          values
          ++ [
            1
            "s"
            { }
            { __functor = 1; }
          ]
        );
        expected = map lib.isFunction (
          values
          ++ [
            1
            "s"
            { }
            { __functor = 1; }
          ]
        );
      };
      test-functionArgs-fidelity = {
        expr = map functionArgs values;
        expected = map lib.functionArgs values;
      };
      test-functionArgs-reads-a-published-map = {
        expr = functionArgs withMap;
        expected = {
          x = false;
        };
      };
    };

  # Each refusal names the door first and the construct last (R6).
  flake.testsError.door-constructor-refusals =
    let
      pin = door: msg: {
        type = "ThrownError";
        msg = "^${door}: ${msg}$";
      };
    in
    {
      test-unknown-field-named = {
        expr = closed {
          hostName = 1;
          colr = 1;
        };
        expectedError = pin "gen-probe[.]door" "'colr' is not an option of this door; the options are closed [(]accepted: 'hostName', 'other'[)] [(]in prelude[.]checkOptions[)]";
      };
      test-missing-field-named = {
        expr = closed { other = 1; };
        expectedError = pin "gen-probe[.]door" "required field 'hostName' is missing [(]required: 'hostName'[)] [(]in prelude[.]checkRequired[)]";
      };
      test-unknown-option-named = {
        expr = options { colr = 1; };
        expectedError = pin "gen-probe[.]options" "'colr' is not an option of this door; the options are closed [(]accepted: 'maxDepth'[)] [(]in prelude[.]checkOptions[)]";
      };
      test-door-spec-typo-named = {
        expr = door {
          name = "gen-probe.door";
          requried = [ "a" ];
        } (x: x);
        expectedError = pin "gen-prelude[.]door" "'requried' is not an option of this door; the options are closed [(]accepted: 'name', 'required', 'optional', 'open', 'optionsStep', 'next'[)] [(]in prelude[.]checkOptions[)]";
      };
      # A door carries no retired fields (owner, 2026-09-28: pre-release, a retired name is carried
      # nowhere): `retired` is an unknown spec field like any other, so a door's former option is
      # refused by the plain unknown-option check, with no replacement text (den-hoag-c54n4).
      test-door-spec-retired-is-an-unknown-option = {
        expr = door {
          name = "gen-probe.door";
          optional = [ "keySemantics" ];
          retired.classes = "`keySemantics`";
        } (x: x);
        expectedError = pin "gen-prelude[.]door" "'retired' is not an option of this door; the options are closed [(]accepted: 'name', 'required', 'optional', 'open', 'optionsStep', 'next'[)] [(]in prelude[.]checkOptions[)]";
      };
      test-door-spec-overlap-named = {
        expr = door {
          name = "gen-probe.door";
          required = [ "a" ];
          optional = [ "a" ];
        } (x: x);
        expectedError = pin "gen-prelude[.]door" "'a' is both required and optional in the contract of 'gen-probe[.]door' [(]in prelude[.]door[)]";
      };
      test-door-spec-missing-name-named = {
        expr = door { } (x: x);
        expectedError = pin "gen-prelude[.]door" "required field 'name' is missing [(]required: 'name'[)] [(]in prelude[.]checkRequired[)]";
      };
      # (v1.2, cell G10) the misplaced option is named, and the door it belongs to.
      test-misplaced-option-named = {
        expr = guardedOptionsStep { } {
          rules = [ ];
          exclusive = true;
        };
        expectedError = pin "gen-probe[.]guarded" "'exclusive' is an option of gen-probe[.]guarded, not a field of this record [(]in prelude[.]checkGuarded[)]";
      };
      test-optionsStep-without-open-named = {
        expr = door {
          name = "gen-probe.badGuard1";
          required = [ "rules" ];
          open = false;
          optionsStep = guardedOptionsStep;
        } (r: r);
        expectedError = pin "gen-prelude[.]door" "'optionsStep' guards a record's fields and is meaningless without open = true [(]in the contract of 'gen-probe[.]badGuard1'[)] [(]in prelude[.]door[)]";
      };
      test-optionsStep-required-overlap-named = {
        expr = door {
          name = "gen-probe.badGuard2";
          required = [ "exclusive" ];
          open = true;
          optionsStep = guardedOptionsStep;
        } (r: r);
        expectedError = pin "gen-prelude[.]door" "'exclusive' is both required here and an option of 'gen-probe[.]guarded' [(]in the contract of 'gen-probe[.]badGuard2'[)] [(]in prelude[.]door[)]";
      };
    };
}
