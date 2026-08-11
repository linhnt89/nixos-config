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
