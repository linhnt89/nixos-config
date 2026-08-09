{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  #
  # Boot
  #

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  #
  # Networking
  #

  networking.hostName = "minipc";
  networking.networkmanager.enable = true;

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
  # Memory / swap
  #

  zramSwap.enable = true;

  #
  # AMD Radeon 780M graphics
  #

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  #
  # Bluetooth
  #

  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  #
  # Security
  #

  security.rtkit.enable = true;

  # Required for hyprlock authentication.
  security.pam.services.hyprlock = {};

  #
  # Audio
  #

  services.pipewire = {
    enable = true;

    alsa.enable = true;
    alsa.support32Bit = true;

    pulse.enable = true;
  };

  #
  # File management
  #

  # NixOS provides proper Thunar integration including
  # D-Bus, systemd and xfconf support.
  programs.thunar = {
    enable = true;

    plugins = [
      pkgs.thunar-archive-plugin
      pkgs.thunar-volman
    ];
  };

  # Virtual filesystem support:
  # Trash, removable devices, MTP and other GIO locations.
  #
  # This automatically enables services.udisks2.
  services.gvfs.enable = true;

  # Thumbnail generation used by Thunar.
  services.tumbler.enable = true;

  #
  # Hyprland
  #

  programs.hyprland = {
    enable = true;
    withUWSM = true;
    xwayland.enable = true;
  };

  #
  # Shell
  #

  programs.zsh.enable = true;

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
  # Bootstrap system tools
  #

  environment.systemPackages = [
    pkgs.git
    pkgs.vim
  ];

  #
  # NixOS compatibility version
  #

  system.stateVersion = "26.05";
}
