# MetaCube NixOS Configuration

- This repository manages MetaCube declaratively with NixOS and Home Manager.
- Keep workstation-wide tools in NixOS/Home Manager and project-specific runtimes in project `devShell`s.
- Inspect Git status and preserve work from parallel branches or worktrees before editing.
- Feature branches should validate with `sudo nixos-rebuild build --flake .#metacube`.
- Treat `nixos-rebuild switch` as machine-global; normally switch only from the integrated canonical `main` checkout.
- New files referenced by this Git-backed flake must be Git-visible before Nix can evaluate them.
- Prefer clear module ownership and avoid duplicating configuration across modules.
- Pi authored configuration belongs under `home/pi/`; credentials and runtime state under `~/.pi/agent/` must remain outside Git.
- When giving manual configuration changes, explain the change first and provide complete changed files rather than partial replacement fragments.
- Before considering a configuration change complete, successfully build the relevant NixOS configuration or clearly report why it could not be built.

## Platform gotchas (verified on MetaCube)

- Hyprland is 0.55.4 with the **Lua config** (`home/hyprland.lua`), so `hyprctl dispatch` arguments are Lua expressions. Legacy forms like `hyprctl dispatch dpms off` fail; use `hyprctl dispatch "hl.dsp.dpms({action='off'})"`. No `hyprctl lockscreen` command exists on 0.55.4.
- hyprlock 0.9.5: `fail_timeout` is a `general` option (not `input-field`); label `position` uses y-up coordinates (valign=top + negative y moves down, valign=bottom + positive y moves up); labels accept pango markup but only valid attributes (`weight='light'` works, `weight='lighter'` renders literally); fingerprint prompt `$FPRINTPROMPT` renders only when fprintd reports a usable device (no fprintd installed on MetaCube — hint stays hidden).
- hypridle 0.1.7 listeners support `on-timeout`/`on-resume`.
- `sudo` requires a password on this machine; validate branches with `nix build .#nixosConfigurations.metacube.config.system.build.toplevel` (same store build as `nixos-rebuild build`).
- The machine has no physical keyboard; automated input uses `nix shell nixpkgs#wtype` (virtual keyboard; caps-lock toggling via wtype is unreliable — test feedback states, not toggling).

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
