{ ... }:

#
# MetaCube Home Manager entry point.
#
# The portable desktop layer (shell/starship/fzf/bat/eza/direnv/delta/git
# structure, common packages incl. Python/Node, and the `gh` package) is
# imported from the nixdev-config flake in flake.nix
# (`nixdev-config.homeManagerModules.desktop`). The modules imported
# below are LOCAL ADAPTERS: they carry only MetaCube-personal settings
# (identity, SSH hosts, appearance, apps, services, Mango/Noctalia,
# Waybar, Pi seed, Firstmate/treehouse/herdr tooling). Ownership is
# documented in docs/nixdev-config-integration.md.
#
{

  imports = [
    ./modules/shell.nix
    ./modules/moshi.nix
    ./modules/git.nix
    ./modules/dev.nix
    ./modules/appearance.nix
    ./modules/apps.nix
    ./modules/services.nix
    ./modules/waybar.nix
  ];

  #
  # User identity
  #

  home.username = "linhnt";
  home.homeDirectory = "/home/linhnt";

  #
  # XDG base directories
  #

  xdg.enable = true;

  #
  # Home Manager compatibility version
  #

  home.stateVersion = "26.05";
}
