{
  config,
  lib,
  pkgs,
  pkgsUnstable,
  ...
}:

#
# MangoWM + Noctalia desktop experiment (Phase 0, parallel opt-in).
#
# Everything this module does is gated behind the single off-by-default
# flag `metacube.experiments.mangoNoctalia.enable` (flip it in
# hosts/metacube/configuration.nix). With the flag off this module is inert
# and the toplevel is unchanged; with the flag on the machine-global delta is
# explicitly bounded to:
#
#   - mango + noctalia packages from the pinned nixpkgs-unstable input
#   - xdg-desktop-portal wiring (wlr/gtk portals) + a display-manager session
#     entry for mango
#
# The nixpkgs modules `programs.mango` / `programs.noctalia` exist only in
# nixpkgs-unstable (nixos/modules/programs/wayland/{mango,noctalia}.nix at
# rev f13ff45), while this evaluation uses the stable nixpkgs input, so their
# (small) effect is replicated inline here; the wiring below mirrors those
# upstream modules verbatim. Noctalia gets no systemd unit: it is started by
# Mango's exec-once.
#
# greetd, boot, Hyprland and the stable session are untouched by construction;
# the guard assertion below fails the build if a mango session ever leaks into
# the greetd command while the experiment flag is on.
#
# See docs/mango-noctalia-experiment.md for the full experiment runbook,
# including the manual opt-in session and rollback path.

let
  cfg = config.metacube.experiments.mangoNoctalia;
in
{
  options.metacube.experiments.mangoNoctalia = {
    enable = lib.mkEnableOption ''
      the bounded MangoWM + Noctalia desktop experiment
      (parallel opt-in session on an unused VT; the stable Hyprland/greetd
      session stays the default and is never modified)
    '';
  };

  config = lib.mkIf cfg.enable {
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

    # Mango desktop entry for UWSM / session lookup.
    services.displayManager.sessionPackages = [ pkgsUnstable.mango ];

    #
    # Machine-global guard: while the experiment is active the greetd default
    # session must keep launching the stable Hyprland session. A mango session
    # may only be entered manually (see docs/mango-noctalia-experiment.md).
    #

    assertions = [
      {
        assertion = !(lib.hasInfix "mango"
          (lib.toLower config.services.greetd.settings.default_session.command));
        message = ''
          metacube.experiments.mangoNoctalia: greetd must keep launching the
          stable Hyprland session while the experiment flag is enabled.
          Mango is a manual opt-in session only (Phase 0/1 boundary); do not
          wire it into greetd. Set the flag off or revert the greetd change.
        '';
      }
    ];

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
  };
}
