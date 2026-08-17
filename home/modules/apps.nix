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
    # Remote desktop (client)
    #
    # RDP client for the Windows 11 Pro laptop on the trusted LAN.
    # Client only: no RDP server, no inbound firewall rule, no
    # Tailscale exposure, no fixed laptop address in this repo.
    # FreeRDP (the RDP engine) arrives as remmina's own dependency.
    # See docs/lan-laptop-access.md.
    #

    pkgs.remmina

    #
    # Archives
    #

    pkgs.xarchiver

    #
    # Images
    #

    pkgs.imv

    #
    # System monitor
    #

    pkgs.btop
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
