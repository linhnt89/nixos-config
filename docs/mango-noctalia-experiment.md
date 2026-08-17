# MangoWM + Noctalia experiment (default login session)

**MangoWM** as compositor with **Noctalia v5** owning bar, notifications,
launcher, OSD, lock screen, wallpaper and settings is the **greetd default
login session** while the experiment flag is enabled. **Hyprland** remains
installed and selectable from the login screen; greetd starts exactly one
session per login, so same-user Hyprland and Mango sessions stay sequential,
never concurrent.

This document is the runbook for the experiment. The original research is the
scout report (`nixos-mangowm-noctalia-scout`); the decisions gating later
phases are the captain-held D-1/D-2/D-3/D-4 holds.

## Single flag

Everything lives behind one flag (the module option defaults to off; the
host now sets it on — durable since the captain completed Phase 1 manual
testing on 2026-08-16):

```nix
# hosts/metacube/configuration.nix
metacube.experiments.mangoNoctalia.enable = true;  # flip to false to roll back
```

Module layout (all gated by that flag; inert when off):

| File | Role |
|---|---|
| `modules/nixos/mango-experiment.nix` | flag definition, pinned unstable Mango/Noctalia packages, portal/session wiring, greetd default-session switch (Mango via UWSM), conditional-default assertions |
| `home/modules/experiment.nix` | generates `~/.config/mango/config.conf`, `~/.config/noctalia/config.toml` and `~/.config/noctalia/palettes/MetaCube.json` from `home/theme.nix` design tokens |
| `scripts/validate-mango-session.sh` | validation checklist (offline `--static` mode + in-session probes) |
| `scripts/test-mango-default-session.sh` | conditional-default + UWSM-path regression tests (wired into `scripts/check.sh`) |

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
   Mango (which also makes Mango selectable from the login screen).
3. The greetd default session command now starts Mango through the UWSM
   wrapper (`uwsm start -e -D mango mango.desktop`), replacing the Hyprland
   default. `modules/nixos/hyprland.nix` declares its default with
   `lib.mkDefault`, so the experiment module takes it over while the flag is
   on and Hyprland comes back as the default when the flag is off.

Everything else is user-scope (config files in the home directory). boot,
kernel params, systemd system units, and the Hyprland stack
(`modules/nixos/hyprland.nix`, `home/hyprland.lua`, Waybar/SwayNC/Fuzzel/
Hyprlock/Hypridle/Hyprpaper) stay installed. The retained Hyprland user
services are conditioned on `XDG_CURRENT_DESKTOP` (`*:mango:*` skips them)
and are therefore skipped in the Mango session while remaining active when
Hyprland is chosen explicitly. That condition is only a fallback guard; it
does not isolate two concurrent sessions. greetd starts exactly one session
command per login, so concurrency cannot arise — the module's
conditional-default assertions fail the build if the default command ever
launches both sessions or drifts from the flag.
No additional Noctalia recommended services are added, avoiding
machine-global `upower`/`power-profiles-daemon` dependencies.

The default command is `tuigreet --time --remember --asterisks --cmd
<start-mango-uwsm>`; the wrapper script is the same shape as Hyprland's
(`modules/nixos/hyprland.nix`) and must never exec the bare `mango` binary —
UWSM is what applies the `mango` plugin
(`XDG_CURRENT_DESKTOP=mango:wlroots`), which the per-session service
conditions above rely on. `scripts/test-mango-default-session.sh` locks in
both the conditional default and the UWSM path.

## Choosing Hyprland from the login screen

At the greetd login screen (tuigreet), press **F3** to open the session
menu and pick **"Hyprland (uwsm-managed)"** (the plain "Hyprland" entry also
exists but does not go through UWSM — prefer the uwsm-managed entry, which
keeps the same session environment the stable session always had). The
choice applies to that login only: after logout, greetd returns with Mango
as the default again. F2 opens a free-form command prompt if you want to
start something else entirely.

## Bluetooth in the Mango session

The stable Hyprland session keeps the legacy blueman tray applet
(`blueman-applet`, started from its XDG autostart entry by the systemd user
manager). In Mango that applet would duplicate Noctalia's built-in Bluetooth
bar widget (one icon in the `tray` widget, one in the `bluetooth` widget), so
the experiment suppresses the applet in Mango only:

- `home/modules/experiment.nix` writes `~/.config/autostart/blueman.desktop`,
  a shadow of the system entry (`/etc/xdg/autostart/blueman.desktop`, from
  `services.blueman.enable`) with `NotShowIn=mango`. The XDG autostart search
  order gives the user-level file precedence, and systemd >= 260 converts
  `NotShowIn=` into an `ExecCondition=` evaluated at service start, so the
  applet is skipped exactly when `XDG_CURRENT_DESKTOP` contains mango — the
  same per-session boundary as the fallback-service condition — and still
  starts in Hyprland.
- Noctalia's built-in Bluetooth widget is the Mango Bluetooth UI and is
  untouched; the general `tray` widget stays, so other tray applications are
  unaffected.
- BlueZ/`hardware.bluetooth` support and `blueman-manager` (the on-click
  action behind the Bluetooth bar icons and Waybar) remain available.
- Flag off (rollback): the shadow file is removed and the system entry
  behaves exactly as before in every session.

Regression coverage: `scripts/test-mango-blueman.sh` (wired into
`scripts/check.sh`) evaluates the flag-on and flag-off configurations and
asserts the shadow exists with `NotShowIn=mango`/`Exec=blueman-applet` when
on and is absent when off.

## Build boundary

The host now sets the flag on, so the plain toplevel build exercises the
experiment state directly (including the conditional-default assertions).
This remains build-only: do not run `nixos-rebuild test` or
`nixos-rebuild switch`, activate Home Manager, or enter the Mango session
from an unmerged branch.

```sh
sudo nixos-rebuild build --flake .#metacube
```

## Login and validation

After this change is merged **and activated by the captain**, Mango is simply
the default: log in normally at the greetd screen and the Mango session
starts through UWSM with Noctalia as the shell. If you were in a Hyprland
login, log out completely and wait for greetd before logging into the Mango
session (F3 at the login screen selects Hyprland explicitly).

The manual VT entry (`exec uwsm start -e -D mango mango.desktop` from a
fresh unused VT) remains supported as a debug path and is what the preflight
check guards, but it is no longer required for a normal login:

```sh
scripts/validate-mango-session.sh --preflight   # only when entering from a VT
```

The preflight refuses to run from inside a graphical session (exit 2 with a
fresh-VT message); if that happens, a graphical session is still active —
log out completely and rerun from the fresh VT.

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

The switch and the Mango entry require captain approval. Build gates per repo
AGENTS.md: `scripts/check.sh` (static checks + `nix flake check` +
non-activating toplevel build) must stay green at every step.

## Success criteria (Phase 1 — completed 2026-08-16)

1. Mango session boots via UWSM with Noctalia as shell; `mmsg get version`
   and `noctalia msg …` IPC respond.
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

Since the default switched to Mango, ongoing checks are: greetd boots to
Mango; Hyprland is reachable via the login screen session menu; the
conditional-default assertions and `scripts/test-mango-default-session.sh`
pass; daily sessions stay regression-free.

## Failure criteria (stop and roll back)

- Any machine-global breakage (greetd/login, boot, systemd system units).
- Lock-screen hang reproduced twice, or keyboard loss after suspend+resume
  (file findings upstream and stop).
- Two or more open upstream issues hit in daily use within the window.
- A required surface proves missing on Mango and no upstream fix lands.

## Rollback

One-line flip: set the flag back to `false`, then, with captain approval, run
`sudo nixos-rebuild switch --flake .#metacube` from the canonical `main`
checkout. The greetd default then returns to the Hyprland UWSM session
(`modules/nixos/hyprland.nix`), the Mango packages/portal/session wiring and
home config files stop being generated, and the Hyprland stack — which was
never removed — remains exactly as before. Optionally remove the home config
files (`~/.config/mango/`, `~/.config/noctalia/`) or restore the previous
Home Manager generation. No system restore is involved.

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