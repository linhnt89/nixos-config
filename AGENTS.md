# MetaCube NixOS Configuration

- This repository manages MetaCube declaratively with NixOS and Home Manager.
- Keep workstation-wide tools in NixOS/Home Manager and project-specific runtimes in project `devShell`s.
- Inspect Git status and preserve work from parallel branches or worktrees before editing.
- Treehouse pool capacity is declared in the repo-root `treehouse.toml` (`max_trees = 8`) and overrides the user-level default in `home/modules/treehouse.nix` (`~/.config/treehouse/config.toml`).
- Feature branches validate with `scripts/check.sh` (static checks, `nix flake check`, non-activating toplevel build — never a switch).
- Treat `nixos-rebuild switch` as machine-global; normally switch only from the integrated canonical `main` checkout.
- New files referenced by this Git-backed flake must be Git-visible before Nix can evaluate them.
- Prefer clear module ownership and avoid duplicating configuration across modules.
- Pi authored configuration belongs under `home/pi/`: `models.json`, `AGENTS.md`, and `openai-server-compaction.json` are read-only declarative links; `settings.json` and `web-search.json` are seeds copied once into runtime-owned files (`~/.pi/agent/settings.json`, `~/.config/pi/web-search.json`) on first activation. Pi owns the runtime files afterwards; the tracked clone is never written at runtime. Re-apply tracked defaults with `pi-apply-defaults`. Credentials and runtime state under `~/.pi/agent/` must remain outside Git. See `docs/pi-settings-boundary.md`.
- The MangoWM + Noctalia desktop experiment is off by default behind `metacube.experiments.mangoNoctalia.enable` (set in `hosts/metacube/configuration.nix`); its modules, runbook and rollback live in `modules/nixos/mango-experiment.nix`, `home/modules/experiment.nix` and `docs/mango-noctalia-experiment.md`. It uses the pinned `nixpkgs-unstable` input (mango/noctalia do not exist on stable).
- When giving manual configuration changes, explain the change first and provide complete changed files rather than partial replacement fragments.
- Before considering a configuration change complete, successfully build the relevant NixOS configuration or clearly report why it could not be built.
- Dependency updates land via Dependabot PRs validated locally with `scripts/check.sh` (static checks + `nix flake check` + non-activating toplevel build; CI is an optional `workflow_dispatch` fallback, `.github/`); the PR-to-switch procedure is `docs/updates-runbook.md`, staleness is reported by `scripts/check-stale.sh`, and the noMistakes tarball pin is bumped only with `scripts/update-no-mistakes.sh` (Dependabot cannot bump tarball inputs). Nix-managed tools are never self-updated, `stateVersion` is never bumped during upgrades, and the shared no-mistakes daemon is restarted only by firstmate after a Nix bump.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
