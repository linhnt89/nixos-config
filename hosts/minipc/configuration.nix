{ pkgs, ... }:

let
  # Session started by greetd after successful authentication.
  #
  # UWSM loads Hyprland's desktop entry rather than executing
  # the Hyprland binary directly. The desktop entry then invokes
  # start-hyprland, which is the supported startup path.
  hyprlandSession = pkgs.writeShellScript "start-hyprland-uwsm" ''
    exec ${pkgs.uwsm}/bin/uwsm \
      start -e -D Hyprland \
      hyprland.desktop
  '';
in
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
  # Fonts
  #

  fonts.packages = [
    pkgs.inter

    pkgs.noto-fonts
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-cjk-serif
    pkgs.noto-fonts-color-emoji

    pkgs.nerd-fonts.jetbrains-mono
  ];

  fonts.fontconfig.defaultFonts = {
    sansSerif = [
      "Inter"
      "Noto Sans"
    ];

    serif = [
      "Noto Serif"
    ];

    monospace = [
      "JetBrainsMono Nerd Font"
    ];

    emoji = [
      "Noto Color Emoji"
    ];
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
  # dconf / GTK infrastructure
  #

  programs.dconf.enable = true;

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

  programs.thunar = {
    enable = true;

    plugins = [
      pkgs.thunar-archive-plugin
      pkgs.thunar-volman
    ];
  };

  services.gvfs.enable = true;
  services.tumbler.enable = true;

  #
  # Hyprland
  #

  programs.hyprland = {
    enable = true;

    # Keep Hyprland managed by UWSM.
    withUWSM = true;

    xwayland.enable = true;
  };

  #
  # Login manager
  #

  services.greetd = {
    enable = true;

    # Prevent boot messages from interfering with the TUI greeter.
    useTextGreeter = true;

    settings = {
      default_session = {
        command =
          "${pkgs.tuigreet}/bin/tuigreet "
          + "--time "
          + "--remember "
          + "--asterisks "
          + "--cmd ${hyprlandSession}";

        user = "greeter";
      };
    };
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
