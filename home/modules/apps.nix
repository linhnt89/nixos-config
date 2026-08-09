{ pkgs, ... }:

{
  #
  # Browser
  #

  programs.firefox.enable = true;

  #
  # Media player
  #

  programs.mpv = {
    enable = true;

    scripts = [
      pkgs.mpvScripts.mpris
    ];

    config = {
      hwdec = "auto-safe";
      save-position-on-quit = true;
      force-window = true;
    };
  };

  services.playerctld.enable = true;

  #
  # PDF/document viewer
  #

  programs.zathura.enable = true;

  #
  # Other desktop applications
  #

  home.packages = [
    #
    # Notifications
    #

    pkgs.libnotify

    #
    # Clipboard
    #

    pkgs.wl-clipboard
    pkgs.cliphist

    #
    # Screenshots
    #

    pkgs.grim
    pkgs.slurp

    #
    # Audio
    #

    pkgs.pavucontrol

    #
    # Network
    #

    pkgs.networkmanagerapplet

    #
    # Archives
    #

    pkgs.xarchiver

    #
    # Images
    #

    pkgs.imv
  ];

  #
  # Default applications
  #

  xdg.mimeApps = {
    enable = true;

    defaultApplicationPackages = [
      pkgs.thunar
      pkgs.xarchiver
      pkgs.imv
      pkgs.zathura
      pkgs.mpv
    ];
  };
}
