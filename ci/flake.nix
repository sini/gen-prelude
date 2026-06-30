{
  inputs = {
    gen.url = "github:sini/gen";
    nixpkgs.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs =
    inputs@{ gen, ... }:
    let
      genPrelude = import ../lib;
    in
    gen.lib.mkCi {
      inherit inputs;
      name = "gen-prelude";
      testModules = ./tests;
      specialArgs = { inherit genPrelude; };
    };
}
