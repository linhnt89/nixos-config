# MangoWM + Noctalia experiment (Phase 0)

Bounded, parallel-opt-in desktop experiment on MetaCube: **MangoWM** as
compositor with **Noctalia v5** owning bar, notifications, launcher, OSD,
lock screen, wallpaper and settings. The stable Hyprland session, greetd and
boot are untouched; Mango is entered manually on an unused VT. Same-user
Hyprland and Mango sessions are sequential, never concurrent.

This document is the runbook for the experiment. The original research is the
scout report (`nixos-mangowm-noctalia-scout`); the decisions gating later
phases are the captain-held D-1/D-2/D-3/D-4 holds.

## Single flag

Everything lives behind one off-by-default flag:

```nix
# hosts/metacube/configuration.nix
metacube.experiments.mangoNoctalia.enable = false;  # flip to true to run
```

Module layout (all gated by that flag; inert when off):

| File | Role |
|---|---|
| `modules/nixos/mango-experiment.nix` | flag definition, pinned unstable Mango/Noctalia packages, portal/session wiring, greetd no-change guard assertion, and the Home Manager bridge |
| `home/modules/experiment.nix` | generates `~/.config/mango/config.conf`, `~/.config/noctalia/config.toml` and `~/.config/noctalia/palettes/MetaCube.json` from `home/theme.nix` design tokens |
| `scripts/validate-mango-session.sh` | Phase-1 validation checklist (offline `--static` mode + in-session probes) |

With the flag off the toplevel build is unchanged (verified by store-path
comparison). No new flake inputs; packages come from the existing pinned
`nixpkgs-unstable` input: **mango 0.15.6**, **noctalia 5.0.0-beta.7**,
uwsm 0.26.6 (ships the `mango` plugin).

## Machine-global impact (flag on)

Explicitly bounded to:

1. `environment.systemPackages` — additive Mango and Noctalia packages from
   the pinned `nixpkgs-unstable` input. Noctalia has no systemd unit here; it
   is started by Mango's `exec-once`.
2. `xdg.portal` wiring (wlr/gtk) and a display-manager session entry for
   Mango.
3. A build-time assertion that greetd's default session command does not
   mention mango.

Everything else is user-scope (config files in the home directory). greetd,
boot, kernel params, systemd system units, and the Hyprland stack
(`modules/nixos/hyprland.nix`, `home/hyprland.lua`, Waybar/SwayNC/Fuzzel/
Hyprlock/Hypridle/Hyprpaper) are untouched and stay installed. The retained
Hyprland user services are conditioned on `XDG_CURRENT_DESKTOP` and are
skipped for the manual Mango session, while remaining active for Hyprland.
That condition is only a fallback guard; it does not isolate two concurrent
sessions. Log out of Hyprland completely before starting Mango, and use the
validation script's `--preflight` check on the fresh VT login.
No additional Noctalia recommended services are added, avoiding
machine-global `upower`/`power-profiles-daemon` dependencies.

## Phase 0 build boundary

This feature branch is build-only. Do not run `nixos-rebuild test` or
`nixos-rebuild switch`, activate Home Manager, or enter the Mango session from
this unmerged branch. Keep the host flag false while validating the default
state:

```sh
sudo nixos-rebuild build --flake .#metacube
```

Build the flag-on state without editing files (lib.mkForce is required because
the host sets the flag explicitly):

```sh
nix build --impure --expr 'let f = builtins.getFlake "path:'"$PWD"'"; in (f.nixosConfigurations.metacube.extendModules { modules = [ ({ lib, ... }: { metacube.experiments.mangoNoctalia.enable = lib.mkForce true; }) ]; }).config.system.build.toplevel'
```

## Captain-approved Phase 1 entry

Only after the change is merged, the captain approves activation, and the
command is run from the canonical `main` checkout with the approved flag-on
configuration, may the machine be activated:

```sh
sudo nixos-rebuild switch --flake .#metacube
```

Before starting Mango, end the Hyprland login completely. Log out of
Hyprland and wait for greetd to return; do not merely switch away from it or
leave it running on another VT. On the fresh unused VT (Ctrl+Alt+F2), log in
as `linhnt`, run the preflight check, and require it to report no Hyprland
process, no other same-user graphical session, and no active fallback service:

```sh
scripts/validate-mango-session.sh --preflight
```

Only then run the following manual opt-in command. This command is also
captain-approved experiment activity; it must not be wired into greetd:

```sh
exec uwsm start -e -D mango mango.desktop
```

`-e -D mango` gives the UWSM session the compositor marker used to keep the
Hyprland fallback services out of the Mango session. UWSM loads its `mango`
plugin, Mango exports `MANGO_INSTANCE_SIGNATURE` to its clients, and Mango's
config starts Noctalia via `exec-once`. Ctrl+Alt+F1 must show greetd rather
than an already-running Hyprland session; leave Mango before starting
Hyprland again. Exit with `mmsg dispatch quit` (or Super+M).

## Validation

```sh
# offline: validates the generated config files (no session needed)
~/nixos-config/scripts/validate-mango-session.sh --static

# stable-session baseline, before entering Mango
scripts/validate-mango-session.sh --footprint-only

# Mango in-session checklist (reload/monitor, tag/widget, and app probes)
scripts/validate-mango-session.sh --launch-apps --footprint

# gate probes (interactive; these are the upstream-bug probes)
scripts/validate-mango-session.sh --lock-loop 20      # Noctalia #3848
scripts/validate-mango-session.sh --suspend-probe     # Mango #1017
```

The switch, Mango entry, lock loop, and suspend probe require captain approval.
Build gates per repo AGENTS.md: `sudo nixos-rebuild build --flake
.#metacube` must stay green at every step.

## Success criteria (all must hold to continue past Phase 1)

1. Mango session boots via UWSM from an unused VT with Noctalia as shell;
   `mmsg get version` and `noctalia msg …` IPC respond.
2. Daily surfaces work on Mango: bar + tray, launcher, notifications,
   control center, wallpaper, OSDs, clipboard history, screenshot.
3. 20 consecutive lock→unlock cycles with zero hangs (Noctalia #3848);
   one suspend→resume with the lock screen usable afterwards (Mango #1017).
4. Existing apps keep working: kitty, Firefox (+XWayland), mpv (MPRIS),
   Thunar, Zathura; screen sharing/recording tested once (Mango #1162).
5. Workspace widget reflects Mango tags correctly (mango-ipc backend).
6. No regressions in the stable Hyprland session.
7. Footprint recorded: run `--footprint-only` in stable Hyprland and
   `--footprint` in Mango; compare Noctalia total RSS with the combined
   Waybar+SwayNC+Fuzzel+Hyprlock+Hypridle+Hyprpaper baseline. The result is
   non-comparable until all six fallback processes are present and measured.
8. Branch stays buildable at every step.

## Failure criteria (stop and roll back)

- Any machine-global breakage (greetd/login, boot, systemd system units).
- Lock-screen hang reproduced twice, or keyboard loss after suspend+resume
  (file findings upstream and stop).
- Two or more open upstream issues hit in daily use within the window.
- A required surface proves missing on Mango and no upstream fix lands.

## Rollback

One-line flip: set the flag back to `false`, then, with captain approval, run
`sudo nixos-rebuild switch --flake .#metacube` from the canonical `main`
checkout. Optionally remove the home config files (`~/.config/mango/`,
`~/.config/noctalia/`) or restore the previous Home Manager generation. The
stable session was never touched, so no system restore is involved.

## Upstream watchlist (open at Phase 0, 2026-08-16)

- Noctalia #3848 — lock screen intermittently hangs on "authenticating".
- Mango #1017 — session lock loses keyboard focus after suspend/resume.
- Mango #1162 — OBS portal "wlroots: no output found".
- Mango #1196 — scenefx blur bleeds outside rounded Noctalia panels
  (worked around: Mango layer blur/shadows off + Noctalia shadows off,
  per docs.noctalia.dev/compositor-settings/mango).
- Noctalia #3367 — Wi-Fi cannot be re-enabled from control center (reported
  on Mango).

## Version lag policy

nixpkgs-unstable trails upstream by ~1 release (Mango 0.16.1 and Noctalia
beta.8 exist upstream). The experiment stays pinned for the window; adopt
bumps deliberately (breaking config changes still land at 0.16.x; Noctalia
migrates config automatically). Bumping means bumping `nixpkgs-unstable` in
`flake.lock` repo-wide, so it must re-validate the stable stack too.
