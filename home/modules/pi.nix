{ config, lib, pkgs, ... }:

let
  #
  # Pi configuration boundary (seed-once runtime files).
  #
  # Two kinds of files are involved:
  #
  # 1. Read-only at runtime (models.json, AGENTS.md,
  #    openai-server-compaction.json): kept as out-of-store symlinks from
  #    the canonical checkout. Pi and its extensions only read these;
  #    the tracked clone is never written.
  #
  # 2. Runtime-writable (settings.json, web-search.json): Pi rewrites
  #    settings.json on every /settings change, /model selection, package
  #    change, and automatically after version updates
  #    (lastChangelogVersion). pi-web-access rewrites web-search.json when
  #    a provider or workflow changes. These two are REAL files in the
  #    runtime locations, seeded from the tracked defaults only when
  #    absent. After seeding, Pi owns them and the tracked clone stays
  #    clean.
  #
  # The tracked home/pi/settings.json and home/pi/web-search.json are
  # declarative defaults / first-run seeds. Re-apply them deliberately
  # with `pi-apply-defaults` (or `nixos-rebuild switch` on a fresh HOME).
  #

  piConfigDir =
    "${config.home.homeDirectory}/nixos-config/home/pi";

  # Runtime-owned agent directory (real files Pi may rewrite at will).
  runtimeAgentDir =
    "${config.home.homeDirectory}/.pi/agent";
in
{
  #
  # Read-only at runtime: declarative out-of-store symlinks
  #

  home.file.".pi/agent/models.json".source =
    config.lib.file.mkOutOfStoreSymlink
      "${piConfigDir}/models.json";

  home.file.".pi/agent/AGENTS.md".source =
    config.lib.file.mkOutOfStoreSymlink
      "${piConfigDir}/AGENTS.md";

  home.file.".pi/agent/openai-server-compaction.json".source =
    config.lib.file.mkOutOfStoreSymlink
      "${piConfigDir}/openai-server-compaction.json";

  #
  # Runtime-writable: seed once, then let Pi own the file
  #
  # No home.file entry for ~/.pi/agent/settings.json or
  # ~/.config/pi/web-search.json: Home Manager's cleanOldGen removes the
  # old leaking symlinks on the first switch, and the activation seed
  # below creates the real files only when absent.
  #

  home.activation.seedPiRuntimeSettings =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      seed() {
        local src="$1" dst="$2"
        if [[ ! -e "$dst" ]]; then
          install -D -m 600 "$src" "$dst"
          _i "Seeded $dst from declarative defaults"
        else
          _i "Keeping existing $dst"
        fi
      }
      seed "${piConfigDir}/settings.json" "${runtimeAgentDir}/settings.json"
      seed "${piConfigDir}/web-search.json" "${config.xdg.configHome}/pi/web-search.json"
    '';

  #
  # pi-apply-defaults: deliberately re-apply tracked defaults to the
  # runtime files (e.g. after updating home/pi/settings.json or
  # home/pi/web-search.json in the repo and rebuilding).
  #

  home.packages = [
    (pkgs.writeShellScriptBin "pi-apply-defaults" ''
      set -euo pipefail

      # Re-apply the tracked declarative Pi defaults to the runtime-owned
      # files. Pi and pi-web-access own the runtime files afterwards; the
      # tracked clone is never written by this script or by Pi.
      #
      # Usage:
      #   pi-apply-defaults           copy tracked defaults to runtime files
      #   pi-apply-defaults --dry-run show what would be copied

      tracked_dir="''${HOME}/nixos-config/home/pi"
      runtime_settings="''${HOME}/.pi/agent/settings.json"
      runtime_web="''${XDG_CONFIG_HOME:-''${HOME}/.config}/pi/web-search.json"

      dry_run=0
      if [[ ''${1:-} == "--dry-run" ]]; then
        dry_run=1
      elif [[ -n ''${1:-} ]]; then
        echo "pi-apply-defaults: unknown option: $1" >&2
        echo "usage: pi-apply-defaults [--dry-run]" >&2
        exit 1
      fi

      apply() {
        local src="$1" dst="$2"
        if [[ ! -f "$src" ]]; then
          echo "pi-apply-defaults: missing tracked source: $src" >&2
          exit 1
        fi
        if [[ -L "$dst" ]]; then
          echo "pi-apply-defaults: refusing: $dst is a symlink (out-of-store link still active?)" >&2
          echo "  Run after switching to the seed-once pi.nix module." >&2
          exit 1
        fi
        if (( dry_run )); then
          echo "would install $src -> $dst"
        else
          install -D -m 600 "$src" "$dst"
          echo "installed $src -> $dst"
        fi
      }

      apply "$tracked_dir/settings.json" "$runtime_settings"
      apply "$tracked_dir/web-search.json" "$runtime_web"
    '')
  ];

  #
  # pi-web-access
  #
  # pi-web-access follows XDG_CONFIG_HOME when it is set and otherwise
  # falls back to ~/.pi. Expose the same runtime file at both locations:
  # the XDG path is the real, runtime-owned file (seeded above); the
  # ~/.pi fallback is an out-of-store symlink to it.
  #

  home.file.".pi/web-search.json".source =
    config.lib.file.mkOutOfStoreSymlink
      "${config.xdg.configHome}/pi/web-search.json";
}
