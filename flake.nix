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

    # Public portable Home Manager modules/profiles, shared with the work
    # WSL2 laptop. The `desktop` role profile provides the portable
    # shell/development layer (zsh/starship/fzf/bat/eza/direnv/delta/git
    # structure + the shared common package set) and `gh` — never `glab`;
    # the opt-in `firstmateTools` module supplies the shared Firstmate
    # toolchain (gh-axi & co, no-mistakes, treehouse, and optionally the
    # pinned herdr binary). Shared toolchain pins are nixdev-config-owned;
    # this consumer declares no treehouse/herdr/no-mistakes inputs.
    #
    # PUBLIC INPUT: fetching requires no GitHub access-token; no
    # credential belongs in nix.conf or NIX_CONFIG. The lock entry pins
    # the rev + narHash and contains no secret. See
    # docs/nixdev-config-integration.md for setup, update, and rollback.
    nixdev-config.url = "github:linhnt89/nixdev-config";
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      nixdev-config,
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

                # The pinned treehouse package the Firstmate toolchain
                # requires, taken from THIS flake's public package output
                # (no treehouse flake input on the consumer side); the
                # agent Home Manager profile consumes it through the same
                # extraSpecialArgs. See docs/firstmate.md in nixdev-config.
                treehousePkg =
                  nixdev-config.packages.${system}.treehouse;
              };

              # Two Home Manager users with a deliberate responsibility
              # split:
              #
              # linhnt — the personal desktop account: the nixdev-config
              # desktop role supplies the portable shell/dev layer
              # (shell/starship/fzf/bat/eza/direnv/delta/git structure,
              # common packages incl. Python/Node) plus `gh`; the local
              # modules under ./home/modules are MetaCube-personal
              # adapters. No agent runtime here.
              #
              # agent — the dedicated restricted AI-agent account (see
              # modules/nixos/agent-runtime.nix): the nixdev-config
              # firstmate role profile supplies the portable shell/git/
              # dev structure plus the shared Firstmate toolchain, and
              # the opt-in assistant module enables Pi (configured in
              # home/agent.nix).
              home-manager.users.linhnt = {
                imports = [
                  nixdev-config.homeManagerModules.desktop
                  ./home/linhnt.nix
                ];
              };

              home-manager.users.agent = {
                imports = [
                  nixdev-config.homeManagerModules.firstmate
                  nixdev-config.homeManagerModules.assistant
                  ./home/agent.nix
                ];
              };
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
