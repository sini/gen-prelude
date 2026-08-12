{
  inputs = {
    gen-harness.url = "github:sini/gen-harness";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{ gen-harness, ... }:
    let
      genPrelude = import ../lib;
    in
    gen-harness.lib.mkCi {
      inherit inputs;
      name = "gen-prelude";
      testModules = ./tests;
      specialArgs = { inherit genPrelude; };
    };
}
