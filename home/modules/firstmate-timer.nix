{ config, lib, ... }:

#
# MetaCube-only opt-in: hourly read-only Dependabot observation timer.
#
# Runs the stable Firstmate command `bin/fm-dependabot-sweep.sh` from the
# private Firstmate home (`~/.config`-independent default `%h/firstmate`,
# i.e. the machine clone of linhnt89/firstmate) on a systemd user timer.
# The sweep inventories open Dependabot PRs for the home's registered
# projects and emits once-only durable wake notifications; it is strictly
# read-only on GitHub and on every project clone (see the command's own
# header). The service adds no lifecycle of its own: no NixOS switch, no
# PR merge, no credential write, no session or daemon management — the
# command's own bounds (FM_DEPENDABOT_TIMEOUT / FM_DEPENDABOT_CALL_TIMEOUT
# / FM_DEPENDABOT_LIMIT, defaults 60s / 20s / 100) bound every run.
#
# Opt-in boundary: this module is imported only by MetaCube's own Home
# Manager configuration (home/linhnt.nix). nixdev-config's standalone
# laptop profile never imports it, so the timer never appears there.
# The option defaults to off; MetaCube turns it on explicitly.
#
# The unit intentionally does NOT hard-pin the command's environment
# overrides (FM_DEPENDABOT_*, FM_GH_AXI_BIN, FM_ROOT_OVERRIDE, ...): they
# keep flowing through from the user environment, and the command's own
# PATH-based gh-axi resolution is preserved by putting the Home Manager
# user profile on PATH (gh-axi lives there).
#
# When the private Firstmate home is absent (or the command has not been
# merged into it yet), ConditionPathExists keeps the unit silent instead
# of failing repeatedly.
#

let
  cfg = config.metacube.firstmate.fmDependabotSweep;

  # The sweep command's default private home. systemd expands %h to the
  # user's home directory; the service pins FM_HOME and WorkingDirectory
  # to the same location so the command's home resolution is unambiguous.
  firstmateHome = "%h/firstmate";
in
{
  options.metacube.firstmate.fmDependabotSweep = {
    enable = lib.mkEnableOption "the hourly read-only FM Dependabot sweep user service/timer (bin/fm-dependabot-sweep.sh from the private Firstmate home)";
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.fm-dependabot-sweep = {
      Unit = {
        Description = "Firstmate read-only Dependabot PR awareness sweep";

        # Harmless when the private Firstmate home (or the command) is
        # absent: the unit is skipped silently instead of failing.
        ConditionPathExists = "${firstmateHome}/bin/fm-dependabot-sweep.sh";
      };

      Service = {
        Type = "oneshot";

        ExecStart = "${firstmateHome}/bin/fm-dependabot-sweep.sh";

        WorkingDirectory = firstmateHome;

        Environment = [
          "FM_HOME=${firstmateHome}"

          # gh-axi resolves from PATH inside the sweep; the Home Manager
          # user profile is where the nixdev-config firstmateTools module
          # installs it. Keep the standard NixOS paths for bash/coreutils.
          "PATH=/etc/profiles/per-user/%u/bin:%h/.nix-profile/bin:/run/current-system/sw/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
        ];
      };
    };

    systemd.user.timers.fm-dependabot-sweep = {
      Unit = {
        Description = "Hourly FM Dependabot sweep timer";
      };

      Timer = {
        # Hourly cadence; Persistent recovers runs missed while the
        # desktop was asleep or off, and the small randomized delay
        # spreads post-wake catch-up runs so they do not herd together.
        OnCalendar = "hourly";
        Persistent = true;
        RandomizedDelaySec = "15m";
      };

      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
