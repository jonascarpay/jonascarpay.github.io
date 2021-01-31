{ pkgs ? import <nixpkgs> { } }: with pkgs;
stdenv.mkDerivation {
  name = "blog";
  src = pkgs.nix-gitignore.gitignoreSource [ ] ./.;
  buildInputs = [ pandoc ];
  builder = ./builder.sh;
}
