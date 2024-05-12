{
  description = "tunez is a general purpose audio metadata library made in zig";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    zig.url = "github:mitchellh/zig-overlay";
    zig.inputs.nixpkgs.follows = "nixpkgs";
    zls.url = "github:haze/zls/pr/hb/configurable-insert-helpers";
    zls.inputs.nixpkgs.follows = "nixpkgs";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    zig,
    zls,
    utils,
  }:
    utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.default = pkgs.mkShell {
        buildInputs = [
          zig.packages.${system}."0.12.0"
          zls.packages.${system}.default
        ];
      };
    });
}
