{
  description = "gen-prelude: vendored, nixpkgs-lib-free pure utilities for the gen ecosystem";

  # NO inputs — gen-prelude depends on nothing. The lib is builtins + vendored copies,
  # so the flake pulls zero nixpkgs (a consumer's lock gains no transitive dependency).
  # The test runner lives in ./ci, which is a separate flake.
  outputs =
    { ... }:
    {
      # `nix flake check` forces the WHNF of every top-level output and nothing deeper, so this root's
      # green quantified over the `lib` SPINE alone: a member of the published surface could throw and
      # the check still exited 0 (measured — den-hoag-z1ta6). Hanging the force on that spine is what
      # makes the green mean "the surface evaluates", and a library needs no new output name for it.
      # The depth is each member's WHNF and no deeper: a retirement tombstone is a published `throw`
      # by design (gen-scope's `buildNodes`), so a deep force is red on a healthy tree.
      lib =
        let
          surface = import ./lib;
        in
        builtins.deepSeq (builtins.mapAttrs (_: builtins.typeOf) surface) surface;
    };
}
