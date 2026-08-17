# MetaCube NixOS Configuration

Declarative NixOS and Home Manager configuration for my MetaCube mini PC.

## System

* Hostname: `metacube`
* User: `linhnt`
* Architecture: `x86_64-linux`
* NixOS: `26.05`
* Desktop: MangoWM + Noctalia (experiment default) / Hyprland fallback
* Session manager: UWSM
* Login manager: greetd + tuigreet
* Home configuration: Home Manager
* Git branch: `main`

## Repository structure

```text
.
├── flake.nix
├── flake.lock
│
├── hosts/
│   └── metacube/
│       ├── configuration.nix
│       └── hardware-configuration.nix
│
├── modules/
│   └── nixos/
│       ├── base.nix
│       ├── desktop.nix
│       ├── fonts.nix
│       ├── hyprland.nix
│       ├── mango-experiment.nix
│       └── ssh.nix
│
├── home/
│   ├── linhnt.nix
│   ├── hyprland.lua
│   └── modules/
│       ├── appearance.nix
│       ├── apps.nix
│       ├── experiment.nix
│       ├── git.nix
│       ├── herdr.nix
│       ├── moshi.nix
│       ├── services.nix
│       ├── shell.nix
│       └── waybar.nix
│
├── scripts/
│   └── validate-mango-session.sh
│
└── docs/
    ├── lan-laptop-access.md
    ├── mango-noctalia-experiment.md
    └── moshi-herdr.md
```

## Architecture

The configuration has three main layers.

### `flake.nix`

The flake is the orchestration layer.

It pins dependencies and defines the NixOS configuration named:

```text
metacube
```

The rebuild target is therefore:

```bash
.#metacube
```

The flake should stay relatively small.

### NixOS modules

System-level configuration lives under:

```text
modules/nixos/
```

These settings affect the machine or provide system infrastructure.

Current modules:

```text
base.nix
    Nix settings
    locale
    networking
    user account
    Zsh system integration
    SSH agent
    zram

desktop.nix
    PipeWire
    Bluetooth
    dconf
    Thunar
    GVFS
    Tumbler

fonts.nix
    installed fonts
    Fontconfig defaults

hyprland.nix
    Hyprland
    UWSM
    greetd / tuigreet (Hyprland default session, lib.mkDefault)
    Hyprlock PAM integration

mango-experiment.nix
    MangoWM + Noctalia experiment (single flag)
    portal and session wiring
    greetd default session switch (Mango via UWSM when enabled;
    Hyprland stays selectable at login)
    conditional-default assertions

ssh.nix
    OpenSSH server (key-only)
    Tailscale client
    interface-scoped firewall (trusted LAN + tailnet)
```

Host-specific settings stay in:

```text
hosts/metacube/configuration.nix
```

Examples:

```text
hostname
bootloader
GPU configuration
system.stateVersion
```

The generated hardware configuration stays in:

```text
hosts/metacube/hardware-configuration.nix
```

Avoid manually editing that file unless there is a specific reason.

### Home Manager modules

User-level configuration lives under:

```text
home/modules/
```

Current modules:

```text
shell.nix
    Zsh
    Starship
    fzf
    bat
    eza
    CLI tools

git.nix
    Git
    Delta
    SSH client
    UWSM SSH-agent environment

appearance.nix
    GTK
    Qt
    cursor
    Kitty
    Fuzzel appearance

apps.nix
    Firefox
    mpv
    Zathura
    desktop applications
    MIME associations

experiment.nix
    MangoWM + Noctalia experiment configuration
    generated only when the experiment is enabled

services.nix
    Mako
    Hypridle
    Hyprlock
    Hyprpaper
    clipboard service
    power menu

waybar.nix
    Waybar configuration and CSS

moshi.nix
    Moshi mobile-terminal host support
    mosh
    tmux

herdr.nix
    Herdr agent session runtime
```

`home/linhnt.nix` is the Home Manager entry point and imports the regular user
modules. The gated `experiment.nix` module is imported by the NixOS experiment
module only when its flag is enabled (it generates the Mango/Noctalia configs
read by the default Mango login session).

The native Hyprland Lua configuration is:

```text
home/hyprland.lua
```

Documentation:

```text
docs/mango-noctalia-experiment.md
    MangoWM + Noctalia experiment runbook and rollback

docs/moshi-herdr.md
    Connecting the Moshi Android app to MetaCube
    and attaching to Herdr sessions

docs/lan-laptop-access.md
    LAN remote use of the Windows 11 Pro laptop
    over RDP (Remmina client)
```

## Where should a new setting go?

Use this decision process.

### Is it machine or operating-system infrastructure?

Use a NixOS module.

Examples:

```text
kernel settings
hardware support
system services
filesystems
networking
Bluetooth daemon
PipeWire
display manager
system users
system fonts
virtualization
```

Prefer:

```text
modules/nixos/
```

If it is specific only to the MetaCube hardware, prefer:

```text
hosts/metacube/configuration.nix
```

### Is it configuration for my user account?

Use Home Manager.

Examples:

```text
Git
Zsh
terminal
browser
CLI tools
Waybar
Mako
Hyprlock
application configuration
user packages
```

Prefer:

```text
home/modules/
```

### Does the application have a NixOS or Home Manager module?

Prefer the module.

For example:

```nix
programs.zathura.enable = true;
```

is preferable to installing Zathura as a plain package when its Home Manager module provides the configuration we need.

### Does it have no useful module?

Install the package directly.

For user software:

```nix
home.packages = [
  pkgs.example
];
```

For machine-wide/bootstrap software:

```nix
environment.systemPackages = [
  pkgs.example
];
```

### Is it a native configuration file?

When appropriate, let Home Manager deploy it.

Example:

```nix
xdg.configFile."hypr/hyprland.lua".source =
  ../hyprland.lua;
```

## Normal rebuild workflow

Work from the repository:

```bash
cd ~/nixos-config
```

Check Git first:

```bash
git status
```

### 1. Build

For normal configuration work, build first:

```bash
sudo nixos-rebuild build --flake .#metacube
```

This evaluates and builds the new system without activating it.

### 2. Switch

If the build succeeds:

```bash
sudo nixos-rebuild switch --flake .#metacube
```

This activates the new generation and makes it the normal boot configuration.

### 3. Verify

Check whichever component changed.

Examples:

```bash
hyprctl configerrors
```

```bash
systemctl --failed
```

```bash
systemctl --user --failed
```

### 4. Commit

After verifying the change:

```bash
git add <changed-files>
git commit -m "Describe the change"
```

## New files and flakes

This repository is a Git-backed flake.

When a new Nix file is created, stage it before trying to build:

```bash
git add path/to/new-file.nix
```

Then run the build.

A new file that is not visible to the flake can otherwise appear to Nix as if it does not exist.

## Safer activation modes

### Build only

```bash
sudo nixos-rebuild build --flake .#metacube
```

Use this first for most changes.

### Temporary test

```bash
sudo nixos-rebuild test --flake .#metacube
```

This activates the configuration without making it the default boot generation.

A reboot returns to the previous boot configuration.

### Activate on next boot

```bash
sudo nixos-rebuild boot --flake .#metacube
```

This makes the new generation the boot default without activating it in the current session.

This is useful for changes involving things such as:

```text
display/login manager
boot configuration
session startup
```

### Normal activation

```bash
sudo nixos-rebuild switch --flake .#metacube
```

Builds, activates, and makes the generation the normal boot choice.

## Recovery

NixOS keeps previous system generations.

### From a running system

Roll back to the previous generation:

```bash
sudo nixos-rebuild switch --rollback
```

### If the graphical session is broken

Switch to another TTY:

```text
Ctrl + Alt + F2
```

Log in and inspect the system.

Useful commands:

```bash
systemctl --failed
```

```bash
systemctl --user --failed
```

```bash
journalctl -b -p warning
```

### If the new system cannot boot correctly

At startup, select a previous NixOS generation from the systemd-boot menu.

## Hyprland session

The graphical (default) session starts through:

```text
greetd
  ↓
tuigreet
  ↓
UWSM
  ↓
hyprland.desktop
  ↓
start-hyprland
  ↓
Hyprland
```

With the MangoWM + Noctalia experiment enabled (the host default), the greetd
default session is instead:

```text
greetd
  ↓
tuigreet
  ↓
UWSM
  ↓
mango.desktop
  ↓
Mango
```

To start Hyprland from the login screen, press F3 in tuigreet and select
**"Hyprland (uwsm-managed)"** — the choice applies to that login only.

Do not start the Hyprland binary directly for the normal session.

To log out cleanly:

```bash
uwsm stop
```

The Fuzzel power menu is available with:

```text
Super + Escape
```

## Important Hyprland shortcuts

```text
Super + Q              Kitty
Super + Space          Fuzzel
Super + E              Thunar

Super + C              Close window
Super + F              Fullscreen
Super + Shift + F      Toggle floating

Super + arrows         Focus window
Super + Shift + arrows Swap windows

Super + 1..0           Switch workspace
Super + Shift + 1..0   Move window to workspace

Super + V              Clipboard history
Super + L              Lock
Super + Escape         Power/session menu

Print                  Region screenshot
Shift + Print          Full screenshot
```

## Monitor

Current primary display:

```text
ViewSonic VX2758-2K-PRO
HDMI-A-1
2560x1440 @ 143.98 Hz
scale 1
```

The mode is explicitly configured in:

```text
home/hyprland.lua
```

## Power management

Current baseline:

```text
AMD P-State             active
driver                  amd-pstate-epp
EPP                     balance_performance
platform profile        balanced
AMDGPU DPM              auto
firmware power mode     45 W
```

No additional power manager such as TLP, auto-cpufreq, or power-profiles-daemon is currently used.

## Secrets

Do not place private credentials directly in ordinary Nix configuration.

In particular, this file is private mutable state:

```text
~/.ssh/id_ed25519
```

It must not be committed to this repository.

The corresponding public key is:

```text
~/.ssh/id_ed25519.pub
```

SSH configuration may be declarative, while private key material remains outside the Nix store.

## State versions

The current values are:

```nix
system.stateVersion = "26.05";
home.stateVersion = "26.05";
```

These are compatibility settings associated with the original installation/configuration state.

Do not change them merely because NixOS or Home Manager is upgraded to a newer release.

## Updating dependencies

Dependency upgrades are deliberate, reviewed changes: Dependabot opens
one targeted PR per input (Nix and npm weekly, GitHub Actions monthly),
and nothing is activated automatically.

**Local validation is authoritative.** Every change — including
Dependabot/update PRs — must pass the repository-owned local check
before merge. It runs static checks, `nix flake check`, and a
non-activating build of the system toplevel; it never switches or
activates anything:

```bash
scripts/check.sh                # static checks + nix flake check + build
```

CI is an optional fallback for an independent clean-run build
(`workflow_dispatch` only), not a required check on PRs or pushes. Real
desktop/system-use validation — building, verifying, and switching on
the machine — remains a manual post-merge captain action (see "Normal
rebuild workflow"). The full procedure — targeted updates,
build/verify/switch, rollback, the no-mistakes daemon restart, and the
canonical-clean-checkout rule — is in:

```text
docs/updates-runbook.md
```

Helpers:

```bash
scripts/check.sh                # local validation gate (authoritative)
scripts/check-stale.sh          # read-only staleness report
scripts/update-no-mistakes.sh   # bump the noMistakes tarball pin (Dependabot cannot)
```

Inspect the current inputs with:

```bash
nix flake metadata
```

Dependency upgrades must be committed together with the resulting
`flake.lock` changes. Never bump `stateVersion` during an upgrade (see
"State versions" above).

## Git workflow

Primary branch:

```text
main
```

Before making a change:

```bash
git status
```

After verifying a change:

```bash
git add <files>
git diff --cached
git commit -m "Describe the change"
```

Keep commits reasonably focused so that configuration changes can be understood or reverted later.

