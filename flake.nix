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
      #
      # ★ THE SURFACE IS THE ROOT, NOT `./lib`. `./.` and `./lib` were two independent constructions
      # of one value and so free to disagree; there is ONE construction site now. gen-prelude has
      # zero dependencies, so its root stays the bare `import ./lib` — a value, with no bag to read
      # and nothing to pin — and the two entry paths are the same expression rather than merely
      # agreeing today.
      lib =
        let
          surface = import ./.;
        in
        builtins.deepSeq (builtins.mapAttrs (_: builtins.typeOf) surface) surface;
    };
}
