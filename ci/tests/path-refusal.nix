# A path as the first argument of a prefix/suffix string test is refused, as nixpkgs lib refuses it:
# a path there would be copied to the store and never match, so the answer would be a silent
# `false` (or the subject unchanged) where nixpkgs throws. `tests` holds the verdict equal to
# nixpkgs' on the same input; `testsError` pins that each refusal fires and names its function.
{ lib, genPrelude, ... }:
let
  p = genPrelude;
  refusedBy = f: !(builtins.tryEval (f ./path-refusal.nix "x")).success;
  pin = name: {
    type = "ThrownError";
    msg = "^gen-prelude[.]${name}: the first argument [(].*[)] is a path value, but only strings are supported$";
  };
  # nixpkgs' own text, to its first sentence: the oracle's side of the same input.
  nixpkgsPin = name: {
    type = "ThrownError";
    msg = "^lib[.]strings[.]${name}: The first argument [(].*[)] is a path value, but only strings are supported[.].*";
  };
in
{
  flake.tests.path-refusal.test-prefix-path-verdicts-match-nixpkgs = {
    expr = {
      hasPrefix = refusedBy p.hasPrefix;
      removePrefix = refusedBy p.removePrefix;
    };
    expected = {
      hasPrefix = refusedBy lib.hasPrefix;
      removePrefix = refusedBy lib.removePrefix;
    };
  };

  flake.testsError.path-refusal = {
    test-hasPrefix-path-refused = {
      expr = p.hasPrefix ./path-refusal.nix "x";
      expectedError = pin "hasPrefix";
    };
    test-removePrefix-path-refused = {
      expr = p.removePrefix ./path-refusal.nix "x";
      expectedError = pin "removePrefix";
    };
    test-nixpkgs-hasPrefix-path-refused = {
      expr = lib.hasPrefix ./path-refusal.nix "x";
      expectedError = nixpkgsPin "hasPrefix";
    };
    test-nixpkgs-removePrefix-path-refused = {
      expr = lib.removePrefix ./path-refusal.nix "x";
      expectedError = nixpkgsPin "removePrefix";
    };
  };
}
