# nixdev-config integration (public portable Home Manager layer)

The desktop Home Manager configuration imports the **desktop role** and the
opt-in **firstmateTools module** of the public repo `linhnt89/nixdev-config`
(the same repo that drives the work WSL2 laptop's dev environment). This
page is the runbook for that input.

## What comes from nixdev-config (`desktop` role + `firstmateTools`)

Added in `flake.nix` via `nixdev-config.homeManagerModules.desktop` (the
profile imports nixdev-config's `shell`, `git`, and `dev` modules and adds
`gh` — never `glab`) and `nixdev-config.homeManagerModules.firstmateTools`
(the opt-in shared Firstmate toolchain):

- **Shell layer**: enablement of `zsh`, `starship` (+ bash/zsh
  integration), `fzf`, `bat`, `eza` and the **common package set** (gitFull,
  openssh, delta, eza, fzf, lazygit, tree, zip, unzip, curl, wget, bat, fd,
  ripgrep, jq, yq-go, direnv, nix-direnv, Node (default `pkgs.nodejs`),
  Python, just, shellcheck).
- **Git structure**: `programs.git` enabled with `gitFull`,
  `init.defaultBranch = "main"`, `push.autoSetupRemote`; `programs.delta`
  enabled with git integration.
- **Dev layer**: `direnv` + `nix-direnv` with shell integrations.
- **Role package**: `gh` (GitHub CLI). `glab` is never installed on the
  desktop.

### Shared Firstmate toolchain (opt-in `firstmateTools` module)

The `firstmateTools` module installs the shared Firstmate toolchain that
used to be built locally: the five axi CLIs (`gh-axi`, `chrome-devtools-axi`,
`lavish-axi`, `tasks-axi`, `quota-axi`, pinned in nixdev-config's
`firstmate/node-tools`), `no-mistakes`, `treehouse`, plus `node`/`git`/`gh`/
`tmux`/`jq` from the common set. All shared package pins are
nixdev-config-owned — this repo declares no `treehouse`/`herdr`/`noMistakes`
flake inputs. The module requires the public treehouse package export, wired
in `flake.nix`:

```nix
home-manager.extraSpecialArgs.treehousePkg =
  nixdev-config.packages.${system}.treehouse;
```

The optional pinned `herdr` binary is a per-machine opt-in
(`nixdev.firstmate.enableHerdr = true;`), enabled in `home/linhnt.nix`
because MetaCube's configured Firstmate backend is Herdr. The refactor's
ownership and timer boundaries are locked in by
`scripts/test-ownership.sh` (run by `scripts/check.sh`).

## What stays local (MetaCube-personal)

`home/linhnt.nix` and `home/modules/*` are **local adapters** carrying
everything nixdev-config deliberately does not: git identity and personal
workflow settings, SSH host identity + the UWSM SSH-agent environment,
zsh history/autosuggestion/syntax-highlighting preferences, fzf widget
behavior, delta UI options, the eza "keep `ls` untouched" override, gh
client behavior (SSH protocol, no HTTPS credential helper), lazygit,
appearance, apps, services (swaync, hyprlock/hypridle/hyprpaper,
Bluetooth/Wi-Fi/power quick settings), Waybar, Mango/Hyprland/Noctalia
(experiment), Pi seed/defaults, the user-level treehouse pool default
(`home/modules/dev.nix`), and the opt-in FM Dependabot sweep timer
(`home/modules/firstmate-timer.nix`, MetaCube-only). `pi-coding-agent`
stays on this repo's `nixpkgs-unstable` lane.

Adopted portable defaults (visible deltas from before the integration):
bat's theme becomes `TwoDark`, eza shows git status, starship/fzf/direnv
gain bash integration, and the common set adds Python, Node, shellcheck,
openssh, lazygit, yq-go, just to the user profile. All are role-neutral
portable defaults owned by nixdev-config; the desktop kept every personal
preference via the adapters.

## Fetching the input

`nixdev-config` is a **public GitHub repository**. The `github:` flake
input needs no GitHub authentication — no `access-tokens` entry in
`nix.conf`, no `NIX_CONFIG` override, no `GH_TOKEN`/`GITHUB_TOKEN`
forwarding:

```bash
nix flake lock --update-input nixdev-config   # re-pin to the latest rev
nix build .#nixosConfigurations.metacube.config.system.build.toplevel
```

Rules:

- **Never commit a token, SSH key, credential-bearing URL, or absolute
  home path** for this input. The flake declares only
  `url = "github:linhnt89/nixdev-config"`; `flake.lock` pins the rev +
  narHash and contains no secret. The same boundary is enforced repo-wide
  by the no-secrets rule in `AGENTS.md`.
- **Never silently substitute a machine-local `path:` input** in the
  committed flake. The input must resolve reproducibly from the pinned
  lock entry for any machine, without local state.

Once a rev is fetched it is cached in the Nix store; later builds reuse
the cache. Because the repository is public, a fresh fetch (new rev, GC'd
cache, new machine, CI runner) never needs a token.

## Update procedure

nixdev-config advances deliberately (its own PRs) and is re-pinned here
only when the new revision is wanted:

```bash
# From a clean checkout:
nix flake lock --update-input nixdev-config

scripts/check.sh --nix-build-only
```

Commit `flake.lock` together with the change — never a bare lock refresh.
A rolling update of every input is `nix flake update`, but the deliberate
way to move this lane is `--update-input nixdev-config`.

The **automated lane** wraps exactly this update with validation, a
lock-only PR, and the canonical fast-forward: `scripts/update-nixdev-config.sh`
(preflight plan with `--dry-run`, unattended with `--yes`). It never
activates the machine and is covered by offline regression tests wired
into `scripts/check.sh`. See `docs/updates-runbook.md`
("Automated nixdev-config bump"). It resolves its two paths portably:
the canonical checkout defaults to `$HOME/firstmate/projects/nixos-config`
and the upstream source to `$HOME/firstmate/projects/nixdev-config`, each
overridable via `NIXDEV_UPDATE_CANONICAL_REPO` / `NIXDEV_UPDATE_NIXDEV_SRC`
(no hardcoded home paths).

Since the input is public, Dependabot can also propose nixdev-config
updates like any other `github:` input (it is no longer listed in the
`.github/dependabot.yml` `ignore` list). Validate those PRs with
`scripts/check.sh` exactly like the stable lane. Updating nixdev-config
does **not** cascade to any other pinned input here — its own inputs
(nixpkgs, home-manager) follow only inside the nixdev-config flake.

## Rollback

The nixdev-config integration is a normal flake input like any other:

1. **Revert the pin**: `git revert` the merge commit that bumped
   `nixdev-config` (or restore the previous `flake.lock`), then
   `sudo nixos-rebuild build --flake .#metacube`.
2. **Full removal** (rare): remove the input from `flake.nix`, drop the
   `nixdev-config.homeManagerModules.desktop` import in `flake.nix`, and
   restore the pre-integration `home/modules/{shell,git,dev}.nix` content —
   the local adapters would otherwise depend on imported enablement.

Because every update is its own generation, a bad bump is reverted by
switching back (`sudo nixos-rebuild switch --rollback`) exactly like any
other update (see `docs/updates-runbook.md`). Rollback never touches
`stateVersion`.

## Verification

`scripts/check.sh` (`--nix-build-only` for plain `nix build`) now also:

- **evaluates the imported desktop Home Manager modules** via
  `nix eval --raw .#nixosConfigurations.metacube.config.home-manager.users.linhnt.home.activationPackage`
  (full user-config evaluation — packages, files, scripts — without
  activating anything), and
- builds the non-activating system toplevel as before.

It never switches or activates the system. Switch remains manual,
post-merge, from the canonical checkout, after explicit approval.