# nixdev-config integration (private portable Home Manager layer)

The desktop Home Manager configuration imports the **desktop role** of the
private repo `linhnt89/nixdev-config` (the same repo that drives the work
WSL2 laptop's dev environment). This page is the runbook for that input.

## What comes from nixdev-config (`desktop` role)

Added in `flake.nix` via `nixdev-config.homeManagerModules.desktop` (the
profile imports nixdev-config's `shell`, `git`, and `dev` modules and adds
`gh` — never `glab`):

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

## What stays local (MetaCube-personal)

`home/linhnt.nix` and `home/modules/*` are **local adapters** carrying
everything nixdev-config deliberately does not: git identity and personal
workflow settings, SSH host identity + the UWSM SSH-agent environment,
zsh history/autosuggestion/syntax-highlighting preferences, fzf widget
behavior, delta UI options, the eza "keep `ls` untouched" override, gh
client behavior (SSH protocol, no HTTPS credential helper), lazygit,
appearance, apps, services (swaync, hyprlock/hypridle/hyprpaper,
Bluetooth/Wi-Fi/power quick settings), Waybar, Mango/Hyprland/Noctalia
(experiment), Pi seed/defaults, and the Firstmate/no-mistakes/treehouse/
herdr integration. `pi-coding-agent` stays on this repo's
`nixpkgs-unstable` lane.

Adopted portable defaults (visible deltas from before the integration):
bat's theme becomes `TwoDark`, eza shows git status, starship/fzf/direnv
gain bash integration, and the common set adds Python, Node, shellcheck,
openssh, lazygit, yq-go, just to the user profile. All are role-neutral
portable defaults owned by nixdev-config; the desktop kept every personal
preference via the adapters.

## Private-input authentication boundary

`nixdev-config` is a **private GitHub repository**. `github:` flake inputs
for private repos are fetched with the standard Nix `access-tokens`
mechanism (Nix manual, "GitHub access tokens"):

```ini
# ~/.config/nix/nix.conf         (operator user)
# /root/.config/nix/nix.conf     (for sudo nixos-rebuild builds/switches)
access-tokens = github.com=<token>
```

`<token>` comes from the existing operator GitHub authentication:

```bash
gh auth login        # once; scopes need repo read on linhnt89/nixdev-config
gh auth token        # prints the token to paste into nix.conf (chmod 600)
```

Rules:

- **Never commit a token, SSH key, credential-bearing URL, or absolute
  home path** for this input. The flake declares only
  `url = "github:linhnt89/nixdev-config"`; `flake.lock` pins the rev +
  narHash and contains no secret. The no-secrets scan in `scripts/check.sh`
  enforces the same boundary repo-wide.
- **Never silently substitute a machine-local `path:` input** in the
  committed flake. The input must resolve reproducibly from the pinned
  lock entry with operator authentication.
- The **one-shot alternative** for ad-hoc builds without editing nix.conf:

  ```bash
  NIX_CONFIG="access-tokens = github.com=$(gh auth token)" nix build ...
  ```

- `scripts/check.sh` forwards `GH_TOKEN`/`GITHUB_TOKEN` into `NIX_CONFIG`
  automatically, so `GH_TOKEN=$(gh auth token) scripts/check.sh` works
  with no nix.conf edits.

Once a rev is fetched it is cached in the Nix store; later builds reuse
the cache. A fresh fetch (new rev, GC'd cache, new machine) needs the
token again.

Permissions needed for `<token>`: read access to `linhnt89/nixdev-config`
only (a fine-grained PAT with `Contents: Read` on that repo, or a classic
PAT with `repo` scope for the account).

## Update procedure

nixdev-config advances deliberately (its own PRs) and is re-pinned here
only when the new revision is wanted:

```bash
# From a clean checkout, as a user with GitHub auth:
NIX_CONFIG="access-tokens = github.com=$(gh auth token)" \
  nix flake lock --update-input nixdev-config
# (or simply `GH_TOKEN=$(gh auth token) nix flake lock --update-input nixdev-config`
#  — nothing in this repo sets the token itself)

GH_TOKEN=$(gh auth token) scripts/check.sh --nix-build-only
```

Commit `flake.lock` together with the change — never a bare lock refresh.
A rolling update of every input is `nix flake update`, but the deliberate
way to move this lane is `--update-input nixdev-config`.

**Dependabot cannot update this input** (its token is scoped to this repo
and cannot fetch a different private repository — it is listed in
`.github/dependabot.yml` `ignore` for that reason). The weekly staleness
report shows the input's locked age; its upstream lookup degrades to
"unresolved" without a cross-repo token. Updating nixdev-config also
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