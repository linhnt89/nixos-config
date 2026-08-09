{ ... }:

{
  imports = [
    ./modules/shell.nix
    ./modules/git.nix
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
