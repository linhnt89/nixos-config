# ownership-regression.nix — assertions backing scripts/test-ownership.sh.
#
# Evaluates the real flake and reports "PASS" only when every assertion
# holds. Locks in two boundaries introduced by the shared-Firstmate
# toolchain refactor:
#
#   1. Ownership boundary: this consumer declares NO treehouse/herdr/
#      noMistakes flake inputs (and no local package-building modules);
#      the shared Firstmate toolchain comes from nixdev-config's opt-in
#      `homeManagerModules.firstmateTools`, wired in flake.nix with the
#      exported `packages.${system}.treehouse` and the pinned herdr
#      enabled for this PC (MetaCube's Firstmate backend is Herdr).
#      The repo-root treehouse.toml capacity policy and the Pi unstable
#      lane stay consumer-owned.
#   2. Timer boundary: the opt-in FM Dependabot sweep user service/timer
#      (home/modules/firstmate-timer.nix) is defined exactly as specified
#      (FM_HOME=%h/firstmate, WorkingDirectory=%h/firstmate,
#      ConditionPathExists on the private home's command, hourly
#      Persistent timer with a small randomized delay) and defaults OFF
#      without the MetaCube opt-in, so the standalone laptop profile never
#      gets it.
#
# Nothing here activates or builds anything — pure evaluation.

let
  f = builtins.getFlake (toString ../.);
  nixpkgs = f.inputs.nixpkgs;
  system = "x86_64-linux";
  home-manager = f.inputs.home-manager;

  on = f.nixosConfigurations.metacube;
  hm = on.config.home-manager.users.linhnt;

  lock = builtins.fromJSON (builtins.readFile ../flake.lock);
  rootInputs = lock.nodes.root.inputs;
  flakeNix = builtins.readFile ../flake.nix;

  # ---------- ownership boundary -----------------------------------------

  noLocalToolchainInputs =
    !(builtins.hasAttr "treehouse" rootInputs)
    && !(builtins.hasAttr "herdr" rootInputs)
    && !(builtins.hasAttr "noMistakes" rootInputs);

  nixdevConfigPinned =
    (rootInputs.nixdev-config or "") != "";

  nixdevConfigProvidesInterface =
    builtins.isPath
      (f.inputs.nixdev-config.homeManagerModules.firstmateTools or null)
    && builtins.isString
      (nixpkgs.lib.getName
        (f.inputs.nixdev-config.packages.${system}.treehouse or null));

  flakeNixDeclaresNoToolchainInputs =
    !(nixpkgs.lib.hasInfix "treehouse.url" flakeNix)
    && !(nixpkgs.lib.hasInfix "herdr.url" flakeNix)
    && !(nixpkgs.lib.hasInfix "noMistakes" flakeNix);

  flakeNixConsumesFirstmateTools =
    nixpkgs.lib.hasInfix "nixdev-config.homeManagerModules.firstmateTools" flakeNix
    && nixpkgs.lib.hasInfix "treehousePkg" flakeNix;

  hasPackage =
    prefix:
    builtins.any
      (p: builtins.match "${prefix}.*" (p.name or "") != null)
      hm.home.packages;

  localModulesGone =
    !(builtins.pathExists ../home/modules/treehouse.nix)
    && !(builtins.pathExists ../home/modules/herdr.nix)
    && !(builtins.pathExists ../home/modules/firstmate.nix)
    && !(builtins.pathExists ../home/firstmate/node-tools);

  devNixNoToolchainImports =
    let
      devNix = builtins.readFile ../home/modules/dev.nix;
      linhntNix = builtins.readFile ../home/linhnt.nix;
    in
    !(nixpkgs.lib.hasInfix "treehouse.nix" devNix)
    && !(nixpkgs.lib.hasInfix "herdr.nix" devNix)
    && !(nixpkgs.lib.hasInfix "firstmate.nix" devNix)
    && !(nixpkgs.lib.hasInfix "treehouse.nix" linhntNix)
    && !(nixpkgs.lib.hasInfix "herdr.nix" linhntNix)
    && !(nixpkgs.lib.hasInfix "firstmate.nix" linhntNix);

  noMistakesUpdaterGone =
    !(builtins.pathExists ../scripts/update-no-mistakes.sh);

  treehousePolicyConsumerOwned =
    builtins.pathExists ../treehouse.toml
    && nixpkgs.lib.hasInfix "max_trees = 8"
      (builtins.readFile ../treehouse.toml);

  laptopProfileNeverGetsTimer =
    let
      laptopProfile =
        builtins.readFile (f.inputs.nixdev-config + "/home/profiles/laptop.nix");
    in
    !(nixpkgs.lib.hasInfix "firstmate-timer" laptopProfile);

  # ---------- timer boundary ----------------------------------------------

  sweepService = hm.systemd.user.services."fm-dependabot-sweep" or null;
  sweepTimer = hm.systemd.user.timers."fm-dependabot-sweep" or null;

  asList =
    v:
    if builtins.isList v then v else [ v ];

  timerEnabledOnMetaCube =
    hm.metacube.firstmate.fmDependabotSweep.enable == true;

  herdrEnabledForMetaCube =
    hm.nixdev.firstmate.enableHerdr == true;

  serviceDefined =
    sweepService != null
    && builtins.elem "%h/firstmate/bin/fm-dependabot-sweep.sh"
      (asList sweepService.Service.ExecStart or [ ])
    && (sweepService.Service.WorkingDirectory or "") == "%h/firstmate"
    && builtins.any
      (e: builtins.match "FM_HOME=%h/firstmate" e != null)
      (asList sweepService.Service.Environment or [ ])
    && builtins.any
      (e: nixpkgs.lib.hasPrefix "PATH=" e
        && nixpkgs.lib.hasInfix "/etc/profiles/per-user/%u/bin" e)
      (asList sweepService.Service.Environment or [ ])
    && (sweepService.Unit.ConditionPathExists or "")
      == "%h/firstmate/bin/fm-dependabot-sweep.sh";

  timerDefined =
    sweepTimer != null
    && (sweepTimer.Timer.OnCalendar or "") == "hourly"
    && (sweepTimer.Timer.Persistent == true
      || (sweepTimer.Timer.Persistent or "") == "true"
      || (sweepTimer.Timer.Persistent or "") == "yes")
    && (sweepTimer.Timer.RandomizedDelaySec or "") == "15m"
    && builtins.elem "timers.target"
      (asList sweepTimer.Install.WantedBy or [ ]);

  # The opt-in gate: a minimal configuration importing ONLY the timer
  # module (as the standalone laptop profile would never do) must keep the
  # option off and define no unit.
  minimal = nixpkgs.lib.evalModules {
    modules = [
      (import ../home/modules/firstmate-timer.nix)
      { _module.check = false; }
    ];
  };
  minimalTimers =
    if builtins.hasAttr "systemd" minimal.config then
      if builtins.hasAttr "user" minimal.config.systemd then
        minimal.config.systemd.user.timers or { }
      else
        { }
    else
      { };

  timerOptInByDefault =
    minimal.config.metacube.firstmate.fmDependabotSweep.enable == false
    && !(builtins.hasAttr "fm-dependabot-sweep" minimalTimers);

  # ---------- checks -------------------------------------------------------

  checks = {
    "lock: no treehouse/herdr/noMistakes root inputs" = noLocalToolchainInputs;
    "lock: nixdev-config is pinned" = nixdevConfigPinned;
    "lock: pinned nixdev-config provides firstmateTools + treehouse output" = nixdevConfigProvidesInterface;
    "flake.nix: declares no toolchain inputs" = flakeNixDeclaresNoToolchainInputs;
    "flake.nix: consumes firstmateTools with treehousePkg" = flakeNixConsumesFirstmateTools;
    "user config: treehouse package present (from nixdev-config)" = hasPackage "treehouse";
    "user config: no-mistakes package present" = hasPackage "no-mistakes";
    "user config: herdr package present (enableHerdr)" = hasPackage "herdr";
    "user config: herdr backend enabled for MetaCube" = herdrEnabledForMetaCube;
    "local toolchain modules and node-tools removed" = localModulesGone && devNixNoToolchainImports;
    "no local update-no-mistakes.sh left over" = noMistakesUpdaterGone;
    "repo treehouse.toml capacity policy still consumer-owned (max_trees = 8)" = treehousePolicyConsumerOwned;
    "nixdev-config laptop profile never gets the timer" = laptopProfileNeverGetsTimer;
    "timer: enabled on MetaCube" = timerEnabledOnMetaCube;
    "timer: service definition exact (FM_HOME/WorkingDirectory/condition/PATH)" = serviceDefined;
    "timer: timer definition exact (hourly/persistent/randomized/timers.target)" = timerDefined;
    "timer: opt-in, off by default without MetaCube config" = timerOptInByDefault;
  };

  failed =
    builtins.filter (n: !checks.${n}) (builtins.attrNames checks);
in
if failed == [ ] then
  "PASS"
else
  "FAIL: " + builtins.concatStringsSep ", " failed