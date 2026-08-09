{ pkgs, ... }:

let
  #
  # Hyprland UWSM session
  #
  # We tell UWSM to load Hyprland's desktop entry rather
  # than executing the Hyprland binary directly.
  #
  # This ensures startup goes through start-hyprland.
  #

  hyprlandSession =
    pkgs.writeShellScript "start-hyprland-uwsm" ''
      exec ${pkgs.uwsm}/bin/uwsm \
        start -e -D Hyprland \
        hyprland.desktop
    '';
in
{
  #
  # Hyprland
  #

  programs.hyprland = {
    enable = true;

    withUWSM = true;

    xwayland.enable = true;
  };

  #
  # Hyprlock PAM authentication
  #

  security.pam.services.hyprlock = {};

  #
  # Login manager
  #

  services.greetd = {
    enable = true;

    # tuigreet runs directly on a TTY.
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
}
