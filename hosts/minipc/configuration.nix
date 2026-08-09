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

  # GTK Bluetooth manager plus its D-Bus/systemd integration.
  services.blueman.enable = true;

  #
  # Security
  #

  security.rtkit.enable = true;

  # Required for hyprlock password authentication.
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
