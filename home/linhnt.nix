{ ... }:

#
# MetaCube Home Manager entry point.
#
# The portable desktop layer (shell/starship/fzf/bat/eza/direnv/delta/git
# structure, common packages incl. Python/Node, and the `gh` package) is
# imported from the nixdev-config flake in flake.nix
# (`nixdev-config.homeManagerModules.desktop`), and the shared Firstmate
# toolchain (gh-axi & co, no-mistakes, treehouse, pinned herdr) from
# `nixdev-config.homeManagerModules.firstmateTools` (wired in flake.nix
# with the exported treehouse package). The modules imported below are
# LOCAL ADAPTERS: they carry only MetaCube-personal settings (identity,
# SSH hosts, appearance, apps, services, Mango/Noctalia, Waybar, Pi seed,
# the user-level treehouse default, and the opt-in FM Dependabot sweep
# timer). Ownership is documented in docs/nixdev-config-integration.md.
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
    ./modules/firstmate-timer.nix
  ];

  #
  # Shared Firstmate toolchain — MetaCube choices
  #
  # This PC's configured Firstmate backend is Herdr, so enable the pinned
  # herdr binary the nixdev-config firstmateTools module ships opt-in
  # (binary only; Firstmate drives all Herdr lifecycle). The Dependabot
  # sweep timer is MetaCube-only by construction: the firstmate-timer
  # module above is imported here and nowhere else.
  #

  nixdev.firstmate.enableHerdr = true;

  metacube.firstmate.fmDependabotSweep.enable = true;

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
