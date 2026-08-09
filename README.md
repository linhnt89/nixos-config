# MetaCube NixOS Configuration

Declarative NixOS and Home Manager configuration for my MetaCube mini PC.

## System

* Hostname: `metacube`
* User: `linhnt`
* Architecture: `x86_64-linux`
* NixOS: `26.05`
* Desktop: Hyprland
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
│       └── hyprland.nix
│
└── home/
    ├── linhnt.nix
    ├── hyprland.lua
    └── modules/
        ├── appearance.nix
        ├── apps.nix
        ├── git.nix
        ├── services.nix
        ├── shell.nix
        └── waybar.nix
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
    greetd / tuigreet
    Hyprlock PAM integration
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

services.nix
    Mako
    Hypridle
    Hyprlock
    Hyprpaper
    clipboard service
    power menu

waybar.nix
    Waybar configuration and CSS
```

`home/linhnt.nix` is the Home Manager entry point and imports these modules.

The native Hyprland Lua configuration is:

```text
home/hyprland.lua
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

The graphical session starts through:

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

The flake currently pins Nixpkgs and Home Manager in:

```text
flake.lock
```

Inspect the current inputs with:

```bash
nix flake metadata
```

Show the flake outputs with:

```bash
nix flake show
```

Dependency upgrades should be done deliberately and committed together with the resulting `flake.lock` changes.

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

