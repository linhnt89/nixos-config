{ pkgs, lib, ... }:

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

  security.pam.services.hyprlock = { };

  #
  # Login manager
  #

  services.greetd = {
    enable = true;

    # tuigreet runs directly on a TTY.
    useTextGreeter = true;

    settings = {
      # Default login session: Hyprland through the UWSM wrapper. This is
      # declared with lib.mkDefault so the MangoWM + Noctalia experiment
      # (modules/nixos/mango-experiment.nix) can take the default over
      # while its flag is enabled; Hyprland stays installed and selectable
      # from the login screen either way (tuigreet session menu, F3 ->
      # "Hyprland (uwsm-managed)"). The experiment module asserts this
      # conditional-default boundary and scripts/test-mango-default-session.sh
      # locks it in.
      default_session = {
        command =
          lib.mkDefault (
            "${pkgs.tuigreet}/bin/tuigreet "
            + "--time "
            + "--remember "
            + "--asterisks "
            + "--cmd ${hyprlandSession}"
          );

        user = "greeter";
      };
    };
  };
}
