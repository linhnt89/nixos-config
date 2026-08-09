{
  description = "Project development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs =
    { nixpkgs, ... }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
          };
        in
        {
          default = pkgs.mkShell {
            packages = [
              #
              # Universal project tooling
              #

              pkgs.just

              #
              # Add project-specific tools here.
              #
              # Examples:
              #
              # pkgs.nodejs
              # pkgs.python3
              # pkgs.go
              # pkgs.rustc
              # pkgs.cargo
              #
            ];
          };
        }
      );
    };
}
