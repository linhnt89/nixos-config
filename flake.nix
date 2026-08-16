{
  description = "NixOS configuration for MetaCube";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Fast-moving packages that we intentionally keep separate
    # from the stable system package set.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    treehouse = {
      url = "github:kunchenguid/treehouse";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Agent-aware terminal/session runtime.
    herdr.url = "github:herdrdev/herdr/v0.8.0";

    # Firstmate requires no-mistakes >= 1.31.2.
    #
    # Pin the current stable Linux amd64 release archive rather
    # than letting Firstmate's bootstrap installer mutate the host.
    noMistakes = {
      url = "https://github.com/kunchenguid/no-mistakes/releases/download/v1.46.0/no-mistakes-v1.46.0-linux-amd64.tar.gz";
      flake = false;
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      treehouse,
      herdr,
      noMistakes,
      ...
    }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.metacube =
        nixpkgs.lib.nixosSystem {
          inherit system;

          # The Mango/Noctalia experiment consumes packages from the pinned
          # nixpkgs-unstable input (see modules/nixos/mango-experiment.nix).
          specialArgs = {
            pkgsUnstable = nixpkgs-unstable.legacyPackages.${system};
          };

          modules = [
            ./hosts/metacube/configuration.nix

            home-manager.nixosModules.home-manager

            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;

              home-manager.extraSpecialArgs = {
                pkgsUnstable =
                  nixpkgs-unstable.legacyPackages.${system};

                inherit
                  treehouse
                  herdr
                  noMistakes
                  ;
              };

              home-manager.users.linhnt =
                import ./home/linhnt.nix;
            }
          ];
        };

      templates.dev = {
        path = ./templates/dev;
        description = "Minimal Nix development environment with direnv";

        welcomeText = ''
          # Development environment

          Enter the directory and run:

          ```console
          direnv allow
          ```

          Add project-specific tools and runtimes to `flake.nix`.

          Commit both `flake.nix` and the generated `flake.lock`.
        '';
      };
    };
}
