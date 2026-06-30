{
  description = "gen-prelude: vendored, nixpkgs-lib-free pure utilities for the gen ecosystem";

  # NO inputs — gen-prelude depends on nothing. The lib is builtins + vendored copies,
  # so the flake pulls zero nixpkgs (a consumer's lock gains no transitive dependency).
  # The test runner lives in ./ci, which is a separate flake.
  outputs =
    { ... }:
    {
      lib = import ./lib;
    };
}
