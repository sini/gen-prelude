{
  description = "gen-prelude: vendored, nixpkgs-lib-free pure utilities for the gen ecosystem";

  # NO inputs — gen-prelude depends on nothing. The lib is builtins + vendored copies,
  # so the flake pulls zero nixpkgs (a consumer's lock gains no transitive dependency).
  # The test runner lives in ./ci, which is a separate flake.
  outputs =
    { ... }:
    {
      # ★ THE SURFACE IS THE ROOT, NOT `./lib`. `./.` and `./lib` were two independent constructions
      # of one value and so free to disagree; there is ONE construction site now. gen-prelude has
      # zero dependencies, but its root is a NULLARY FUNCTION rather than a bare value
      # (den-hoag-iev2q): `import ./. { }` is the one call text every roster member answers to,
      # leaf or not, and the two entry paths stay the same expression once applied.
      lib = import ./. { };
    };
}
