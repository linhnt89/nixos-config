{ pkgs, ... }:

{
  #
  # Locale
  #

  time.timeZone = "Asia/Ho_Chi_Minh";

  i18n.defaultLocale = "en_US.UTF-8";

  #
  # Nix
  #

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  nix.settings.auto-optimise-store = true;

  #
  # Memory
  #

  zramSwap.enable = true;

  #
  # Networking
  #

  networking.networkmanager.enable = true;

  #
  # SSH
  #

  # One ssh-agent for the user session.
  programs.ssh.startAgent = true;

  #
  # Shell
  #

  programs.zsh.enable = true;

  # Make completion definitions from system packages
  # visible to Zsh.
  environment.pathsToLink = [
    "/share/zsh"
  ];

  #
  # User
  #

  users.users.linhnt = {
    isNormalUser = true;
    description = "linhnt";

    extraGroups = [
      "networkmanager"
      "wheel"
    ];

    shell = pkgs.zsh;
  };

  #
  # Small bootstrap toolset
  #

  environment.systemPackages = [
    pkgs.git
    pkgs.vim
  ];

  #
  # Setup Garbage Collector
  #
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
}
