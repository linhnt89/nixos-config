{ pkgs, ... }:

{
  #
  # dconf / GTK infrastructure
  #

  programs.dconf.enable = true;

  #
  # Audio
  #

  security.rtkit.enable = true;

  services.pipewire = {
    enable = true;

    alsa.enable = true;
    alsa.support32Bit = true;

    pulse.enable = true;
  };

  #
  # Bluetooth
  #

  hardware.bluetooth.enable = true;

  services.blueman.enable = true;

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

  #
  # GIO virtual filesystem support.
  #
  # Used for things such as Trash and removable/media
  # locations in desktop applications.
  #

  services.gvfs.enable = true;

  #
  # Thumbnail service used by Thunar.
  #

  services.tumbler.enable = true;
}
