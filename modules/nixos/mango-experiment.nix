{ config
, lib
, pkgs
, pkgsUnstable
, ...
}:

#
# MangoWM + Noctalia desktop experiment (default login session).
#
# Everything this module does is gated behind the single flag
# `metacube.experiments.mangoNoctalia.enable` (flip it in
# hosts/metacube/configuration.nix — the host keeps it on since the
# captain's Phase 1 manual testing, 2026-08-16). With the flag off this
# module is inert and the toplevel is unchanged; with the flag on the
# machine-global delta is explicitly bounded to:
#
#   - mango + noctalia packages from the pinned nixpkgs-unstable input
#   - xdg-desktop-portal wiring (wlr/gtk portals) + a display-manager session
#     entry for mango
#   - the greetd default session: Mango is started through the UWSM wrapper
#     (`uwsm start -e -D mango mango.desktop`), replacing the Hyprland
#     default that hyprland.nix declares with lib.mkDefault
#
# The Mango NixOS module exists only in nixpkgs-unstable
# (nixos/modules/programs/wayland/mango.nix at rev f13ff45), while this
# evaluation uses the stable nixpkgs input, so the required Mango package,
# portal and session wiring is replicated inline here. Noctalia is added as a
# package only; it gets no systemd unit and is started by Mango's exec-once.
#
# Hyprland and boot stay installed: programs.hyprland (modules/nixos/
# hyprland.nix) keeps providing the Hyprland session entries, so the stable
# session remains reachable from the login screen by selecting ``Hyprland
# (uwsm-managed)`` in tuigreet's session menu (F3). Only a single greetd
# session command exists, so Hyprland and Mango are never auto-started
# together; the assertions below protect that conditional-default and
# sequential-session boundary, and scripts/test-mango-default-session.sh
# locks in the UWSM path (wrapper script content, never a bare `mango`).
#
# See docs/mango-noctalia-experiment.md for the full experiment runbook,
# including choosing Hyprland from the login screen and the rollback path.

let
  cfg = config.metacube.experiments.mangoNoctalia;

  # The exact UWSM invocation validated during Phase 1 (same shape as the
  # Hyprland wrapper in modules/nixos/hyprland.nix). uwsm resolves
  # mango.desktop from the display-manager session data and applies its
  # mango plugin (XDG_CURRENT_DESKTOP=mango:wlroots), which is what the
  # fallback-service conditions in home/modules/experiment.nix rely on.
  mangoSession =
    pkgs.writeShellScript "start-mango-uwsm" ''
      exec ${pkgsUnstable.uwsm}/bin/uwsm \
        start -e -D mango \
        mango.desktop
    '';

  # Conditional-default and sequential-session boundary, active in both flag
  # states: the greetd default session command must launch Mango exactly when
  # the flag is enabled, and must never bundle a Hyprland session into the
  # same command while Mango is the default (greetd starts one session per
  # login, so a command naming both sessions would be a bug). The UWSM path
  # inside the wrapper script is additionally locked in by
  # scripts/test-mango-default-session.sh (a bare `mango` exec is forbidden).
  assertions =
    let
      defaultCmd =
        config.services.greetd.settings.default_session.command or "";
      lowerCmd = lib.toLower defaultCmd;
    in
    [
      {
        assertion = (lib.hasInfix "mango" lowerCmd) == cfg.enable;
        message = ''
          metacube.experiments.mangoNoctalia: the greetd default session must
          launch Mango exactly while the experiment flag is enabled — found
          the flag ${
            if cfg.enable then
              "on but the greetd default session does not start Mango"
            else
              "off but the greetd default session still starts Mango"
          }. Set the flag back or fix the greetd default session in
          modules/nixos/hyprland.nix / modules/nixos/mango-experiment.nix.
        '';
      }
      {
        assertion = !cfg.enable || !(lib.hasInfix "hyprland" lowerCmd);
        message = ''
          metacube.experiments.mangoNoctalia: while the flag is enabled the
          greetd default session must start Mango only — the command must not
          also launch the Hyprland session (sessions are sequential, never
          concurrent). Choose Hyprland explicitly from the login screen session
          menu instead of bundling it into the default command.
        '';
      }
    ];
in
{
  options.metacube.experiments.mangoNoctalia = {
    enable = lib.mkEnableOption ''
      the MangoWM + Noctalia desktop experiment: while enabled, the greetd
      default login session is Mango started through UWSM (`uwsm start -e -D
      mango mango.desktop`); Hyprland stays installed and remains selectable
      from the login screen
    '';
  };

  # The assertions themselves are defined in the `let` above; they are
  # applied unconditionally (both flag states) via the merge below.
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      #
      # Additive packaging from the pinned nixpkgs-unstable input.
      #

      environment.systemPackages = [
        pkgsUnstable.mango
        pkgsUnstable.noctalia
      ];

      #
      # Portal wiring — mirrors programs.mango from nixpkgs-unstable
      # (nixos/modules/programs/wayland/mango.nix at f13ff45).
      #

      xdg.portal = {
        enable = true;

        extraPortals = [
          pkgs.xdg-desktop-portal-wlr
          pkgs.xdg-desktop-portal-gtk
        ];

        config.mango = {
          default = [
            "gtk"
          ];

          "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
          "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
          "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];

          # wlr does not have this interface, let gtk handle
          "org.freedesktop.impl.portal.Inhibit" = [ "gtk" ];
        };
      };

      # Mango desktop entry for UWSM / session lookup (also makes Mango
      # selectable from the login screen session menu).
      services.displayManager.sessionPackages = [ pkgsUnstable.mango ];

      #
      # greetd default session: start Mango through the UWSM wrapper (the
      # same wrapper shape as Hyprland's in modules/nixos/hyprland.nix, which
      # declares its default with lib.mkDefault so this plain assignment takes
      # over while the flag is on). Hyprland stays installed and reachable via
      # tuigreet's explicit session selection. Overriding lib.mkDefault here
      # also means the sequential-session boundary holds by construction:
      # greetd starts exactly one session command per login.
      #

      services.greetd.settings.default_session.command =
        "${pkgs.tuigreet}/bin/tuigreet "
        + "--time "
        + "--remember "
        + "--asterisks "
        + "--cmd ${mangoSession}";

      #
      # User-scope half of the experiment: config generation for Mango and
      # Noctalia lives in the Home Manager module (gated by the same flag).
      #

      home-manager.users.linhnt = {
        imports = [
          ../../home/modules/experiment.nix
        ];

        metacube.experiments.mangoNoctalia.enable = cfg.enable;
      };
    })

    # Conditional-default and sequential-session boundary (see the
    # comment above the assertions).
    { inherit assertions; }
  ];
}
