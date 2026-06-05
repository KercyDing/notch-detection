{
  description = "Env without SFrame bug on my CachyOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig-overlay.url = "github:mitchellh/zig-overlay"; 
  };

  outputs = { self, nixpkgs, zig-overlay }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          zig-overlay.packages.${system}."0.16.0"
          pkgs.glibc
          pkgs.stdenv.cc
        ];

        shellHook = ''
          echo "Done."
          zig version
        '';
      };
    };
}