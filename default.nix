{ pkgs ? import <nixpkgs> {} }: with pkgs;
stdenv.mkDerivation {
  name = "blog";
  src = pkgs.nix-gitignore.gitignoreSource [] ./.;
  buildInputs = [ pandoc git ];
  installPhase = "bash build.sh";
}
