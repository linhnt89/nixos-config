{
  description = "NixOS configuration for MetaCube";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      ...
    }:
    {
      nixosConfigurations.metacube =
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            ./hosts/metacube/configuration.nix

            home-manager.nixosModules.home-manager

            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

              home-manager.users.linhnt =
                import ./home/linhnt.nix;
            }
          ];
        };
    };
}
