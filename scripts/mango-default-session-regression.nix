# mango-default-session-regression.nix — assertions backing
# scripts/test-mango-default-session.sh.
#
# Evaluates the real flake in both experiment states and reports "PASS" only
# when every assertion holds. Locks in the conditional greetd default
# session (modules/nixos/mango-experiment.nix):
#
#   flag on  -> greetd default_session.command starts the start-mango-uwsm
#               wrapper (never a Hyprland session bundled into the same
#               command, never the bare `mango` binary — the wrapper
#               content itself is checked at the source level by the bash
#               test); the display-manager session list keeps both Mango and
#               the Hyprland fallback entries selectable at login.
#   flag off -> greetd default_session.command stays the unchanged
#               start-hyprland-uwsm wrapper (no mango anywhere).
#
# Flag-on state comes from the host config as built by the flake
# (hosts/metacube/configuration.nix sets the flag on); flag-off state comes
# from a rebuilt system with the experiment flag forced off. Nothing here
# activates or builds anything — pure evaluation.

let
  f = builtins.getFlake (toString ../.);
  nixpkgs = f.inputs.nixpkgs;
  system = "x86_64-linux";
  pkgsUnstable = f.inputs.nixpkgs-unstable.legacyPackages.${system};
  home-manager = f.inputs.home-manager;

  on = f.nixosConfigurations.metacube;
  onCmd = on.config.services.greetd.settings.default_session.command;
  onLower = nixpkgs.lib.toLower onCmd;

  # Same module wiring as flake.nix, with the experiment flag forced off.
  off = nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = { inherit pkgsUnstable; };
    modules = [
      (import ../hosts/metacube/configuration.nix)
      home-manager.nixosModules.home-manager
      {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = {
          inherit pkgsUnstable;
          treehouse = f.inputs.treehouse;
          herdr = f.inputs.herdr;
          noMistakes = f.inputs.noMistakes;
        };
        home-manager.users.linhnt = import ../home/linhnt.nix;
      }
      { metacube.experiments.mangoNoctalia.enable = nixpkgs.lib.mkForce false; }
    ];
  };
  offCmd = off.config.services.greetd.settings.default_session.command;
  offLower = nixpkgs.lib.toLower offCmd;

  onSessions = on.config.services.displayManager.sessionData.sessionNames;
  offSessions = off.config.services.displayManager.sessionData.sessionNames;

  checks = {
    "flag-on: experiment flag actually on" =
      on.config.metacube.experiments.mangoNoctalia.enable;
    "flag-on: toplevel evaluates (module assertions pass)" =
      builtins.isString on.config.system.build.toplevel.drvPath;
    "flag-on: default session starts mango (start-mango-uwsm wrapper)" =
      nixpkgs.lib.hasInfix "start-mango-uwsm" onCmd;
    "flag-on: default session still uses tuigreet" =
      nixpkgs.lib.hasInfix "tuigreet" onCmd;
    "flag-on: default session has no hyprland session bundled" =
      !(nixpkgs.lib.hasInfix "hyprland" onLower);
    "flag-on: mango session entry selectable at login" =
      builtins.elem "mango" onSessions;
    "flag-on: hyprland fallback entry still selectable at login" =
      builtins.elem "hyprland" onSessions
      && builtins.elem "hyprland-uwsm" onSessions;
    "flag-off: experiment flag actually off" =
      !off.config.metacube.experiments.mangoNoctalia.enable;
    "flag-off: toplevel evaluates (module assertions pass)" =
      builtins.isString off.config.system.build.toplevel.drvPath;
    "flag-off: default session starts hyprland (start-hyprland-uwsm wrapper)" =
      nixpkgs.lib.hasInfix "start-hyprland-uwsm" offCmd;
    "flag-off: default session has no mango" =
      !(nixpkgs.lib.hasInfix "mango" offLower);
    "flag-off: no mango session entry" =
      !(builtins.elem "mango" offSessions);
  };

  failed =
    builtins.filter (n: !checks.${n}) (builtins.attrNames checks);
in
if failed == [ ] then
  "PASS"
else
  "FAIL: " + builtins.concatStringsSep ", " failed