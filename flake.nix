{
  description = "blog";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { nixpkgs, flake-utils, ... }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      blog = pkgs.stdenv.mkDerivation {
        name = "blog";
        src = ./.;
        buildInputs = [ pkgs.pandoc ];
        builder = ./builder.sh;
      };
    in
    { defaultPackage = blog; });
}
