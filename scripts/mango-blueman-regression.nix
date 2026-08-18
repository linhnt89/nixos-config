# mango-blueman-regression.nix — assertions backing scripts/test-mango-blueman.sh.
#
# Evaluates the real flake in both experiment states and reports "PASS" only
# when every assertion holds. See the lifecycle note in home/modules/experiment.nix
# (bluemanAutostartEntry) for the mechanism being locked in.
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
  onXdg = on.config.home-manager.users.linhnt.xdg.configFile;
  onText = onXdg."autostart/blueman.desktop".text or null;
  onLines =
    if onText == null then [ ]
    else builtins.filter builtins.isString (builtins.split "\n" onText);

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
          # Same wiring as flake.nix: the shared Firstmate toolchain
          # comes from nixdev-config (no treehouse/herdr/noMistakes
          # inputs on the consumer side anymore).
          treehousePkg =
            f.inputs.nixdev-config.packages.${system}.treehouse;
        };
        home-manager.users.linhnt = {
          imports = [
            f.inputs.nixdev-config.homeManagerModules.desktop
            f.inputs.nixdev-config.homeManagerModules.firstmateTools
            ../home/linhnt.nix
          ];
        };
      }
      { metacube.experiments.mangoNoctalia.enable = nixpkgs.lib.mkForce false; }
    ];
  };
  offXdg = off.config.home-manager.users.linhnt.xdg.configFile;

  checks = {
    "flag-on: autostart/blueman.desktop present" =
      builtins.hasAttr "autostart/blueman.desktop" onXdg;
    "flag-on: [Desktop Entry] section" =
      builtins.elem "[Desktop Entry]" onLines;
    "flag-on: Exec=blueman-applet" =
      builtins.elem "Exec=blueman-applet" onLines;
    "flag-on: Type=Application" =
      builtins.elem "Type=Application" onLines;
    "flag-on: NotShowIn=mango" =
      builtins.elem "NotShowIn=mango" onLines;
    "flag-off: autostart/blueman.desktop absent" =
      !(builtins.hasAttr "autostart/blueman.desktop" offXdg);
    "flag-off: experiment flag actually off" =
      !off.config.metacube.experiments.mangoNoctalia.enable;
  };

  failed =
    builtins.filter (n: !checks.${n}) (builtins.attrNames checks);
in
if failed == [ ] then
  "PASS"
else
  "FAIL: " + builtins.concatStringsSep ", " failed
