{
  description = "blog";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  inputs.md-headerfmt.url = "github:jonascarpay/md-headerfmt";
  inputs.md-headerfmt.inputs.nixpkgs.follows = "nixpkgs";

  outputs = { nixpkgs, flake-utils, md-headerfmt, ... }: flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      blog = pkgs.stdenv.mkDerivation {
        name = "blog";
        src = ./.;
        buildInputs = [ pkgs.pandoc pkgs.graphviz ];
        builder = ./builder.sh;
      };
    in
    {
      defaultPackage = blog;
      defaultApp = pkgs.writeShellScriptBin "serve-blog" ''
        ${pkgs.httplz}/bin/httplz ${blog}
      '';
      devShell = pkgs.mkShell {
        packages = [
          md-headerfmt.defaultPackage.${system}
          pkgs.graphviz
          pkgs.pandoc
        ];
      };
    });
}
