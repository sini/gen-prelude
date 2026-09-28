# `resolve`'S REGISTRY CHECK FIRES AT APPLICATION, NOT ONLY BEHIND A DOOR CALL (den-hoag-7gp66 P2).
#
# `door.nix` proves every `resolve` refusal is catchable, but only by applying the returned door to
# a `ref` — and that leaves the gap this file closes: `resolve` is curried (`r: … in door: ref: …`),
# so a bare `resolve <bad registry>` with NEITHER `door` NOR `ref` ever supplied returns a lambda
# unforced past WHNF, and a lambda's WHNF is itself — the registry's own `checkOptions`/
# `checkRequired` violation sat unread. MEASURED (report Q3): `tryEval (seq (resolve {}) null)`
# answered `success = true` while `tryEval (seq (resolve {} "d" "x") null)` answered `false` for the
# same bad registry — the check fired only once a caller happened to apply both `door` and `ref`, so
# a registry built once and handed to many call sites (the shared-registry shape this door exists
# for) admitted a bad record at construction and refused it only much later, wherever it was first
# resolved against. (Those measurements are of the pre-P2 shape, `resolve registry door ref`. Since P2
# the registry is resolve's SECOND record step, `resolve opts registry door ref`, and both steps are
# `prelude.door`s, which force their check at their own application — the cells below apply `{ }`
# options and then the registry.)
#
# `seq`, not `deepSeq`: WHNF of `resolve`'s own return, no field read and no door/ref applied — the
# strictly narrower predicate `door.nix`'s `deepSeq`-based `refused` cannot discriminate, since
# `deepSeq` forces straight through to the guard regardless of how it is reached.
{ genPrelude, ... }:
let
  inherit (genPrelude) resolve;

  refusesAtApplication = e: !(builtins.tryEval (builtins.seq e null)).success;
  answersAtApplication = e: (builtins.tryEval (builtins.seq e null)).success;

  entries = {
    a = {
      name = "a";
    };
  };
  isCanonical = v: k: (v.name or null) == k;
in
{
  flake.tests.door-application-strictness = {
    # ★ LIVE CONTROL FOR THE WHOLE SUITE, first: `tryEval`+`seq` catches an ordinary throw, and a
    # non-throwing value answers. Without this, every `refusesAtApplication` cell below is equally
    # consistent with a predicate that reads `false` no matter what it is handed.
    test-control-tryeval-seq-catches-an-ordinary-throw = {
      expr = refusesAtApplication (throw "control probe, not this suite's subject");
      expected = true;
    };
    test-control-tryeval-seq-answers-a-non-throwing-value = {
      expr = answersAtApplication 1;
      expected = true;
    };

    # FIXED: a registry missing a required field is refused at `resolve`'s own application — no
    # door, no ref.
    test-resolve-missing-required-field-refused-at-application = {
      expr = refusesAtApplication (resolve { } { });
      expected = true;
    };
    test-resolve-missing-isCanonical-refused-at-application = {
      expr = refusesAtApplication (
        resolve { } {
          inherit entries;
        }
      );
      expected = true;
    };
    # C3: the registry record is closed (R5) — an unknown field is refused at application too.
    test-resolve-unknown-option-refused-at-application = {
      expr = refusesAtApplication (
        resolve { } {
          inherit entries isCanonical;
          hintOf = "x";
        }
      );
      expected = true;
    };
    # A valid registry answers at bare application: the fix must not turn a good registry strict
    # beyond its own checks (no field of `entries` is dragged in merely by constructing the door).
    test-resolve-valid-registry-answers-at-application = {
      expr = answersAtApplication (
        resolve { } {
          inherit entries isCanonical;
        }
      );
      expected = true;
    };
    # Regression pin: the door returned still resolves once applied, unchanged by forcing `checked`
    # earlier.
    test-resolve-still-resolves-once-applied = {
      expr = (resolve { } { inherit entries isCanonical; }) "gen-probe.door" "a";
      expected = "a";
    };
  };
}
