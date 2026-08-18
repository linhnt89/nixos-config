# Updates runbook

How dependency updates land in this repository, and how to take one from
a merged PR to a verified running system. This is the authoritative
procedure; the README section "Updating dependencies" is the short form.

## Principles

- **Updates are deliberate, reviewed, and locally build-verified.**
  Dependabot opens targeted per-dependency PRs; human-authored changes
  (and any non-eligible PR) must pass the repository's local gate
  `scripts/check.sh` before merge; nothing is activated automatically,
  ever. Eligible Dependabot version-update PRs are squash-auto-merged by
  GitHub itself (see "Dependabot" below) once the repository's own
  merge requirements are met — with no required checks they may merge
  promptly, so the post-merge machine verification in "From merged
  update to a running system" is the real safety net for those.
- **Never self-update Nix-managed tools.** `no-mistakes update`,
  `herdr update`, `treehouse update`, `pi update` and `npm install -g`
  are the wrong path on this host: every tool is immutable in the Nix
  store. Versions change only through the repo pins (nixdev-config owns
  the shared Firstmate toolchain; this repo owns nixpkgs/nixpkgs-unstable/
  home-manager/nixdev-config pins and the Pi lane), a rebuild, and
  (after approval) a switch.
- **Never bump `stateVersion`** (`system.stateVersion` /
  `home.stateVersion`, currently `26.05`) during an upgrade. They are
  compatibility settings tied to the original installation. See the
  NixOS wiki "When do I update stateVersion".

## Update lanes

| Lane | Pin | How it moves |
| --- | --- | --- |
| Stable system packages | `nixpkgs` input (`nixos-26.05`) | Dependabot `stable-lane` PR (grouped with home-manager) or `nix flake update nixpkgs` |
| Pi lane (unstable) | `nixpkgs-unstable` input | Dependabot individual PR or `nix flake update nixpkgs-unstable` |
| Home Manager | `home-manager` (`release-26.05`, follows nixpkgs) | moves with `nixpkgs`; Dependabot |
| nixdev-config | `nixdev-config` (public repo, `github:linhnt89/nixdev-config`; desktop's portable Home Manager layer **and** the shared Firstmate toolchain) | Dependabot PR, `nix flake lock --update-input nixdev-config`, or `scripts/update-nixdev-config.sh` (automated narrow lane); see `docs/nixdev-config-integration.md` |
| CI actions | `.github/workflows/*` | Dependabot github-actions PR (monthly) |

Shared Firstmate toolchain pins (treehouse, herdr, no-mistakes, and the
axi CLIs) are **nixdev-config-owned** since the firstmateTools refactor:
this repo declares no `treehouse`/`herdr`/`noMistakes` flake inputs and no
local node-tools pin set. Bumps for those land in
`linhnt89/nixdev-config` (its own Dependabot + PRs) and reach this machine
after the nixdev-config pin above is updated and the machine is rebuilt.

Notes:

- Updating `nixpkgs` cascades to `home-manager` (its input follows
  ours).
- `nixpkgs-unstable` is excluded from the `stable-lane` Dependabot group
  on purpose: the Pi lane should only move when a Pi update is actually
  wanted, not silently with every stable bump. Its individual Dependabot
  PRs are subject to the same auto-merge as every other eligible bot PR;
  deliberate movement is enforced by the Dependabot schedule, not by
  review.
- `templates/dev/flake.nix` pins `nixos-26.05` for project dev shells;
  it is a separate surface, only touched at branch migrations.

## Dependabot

Config: `.github/dependabot.yml`. Weekly on Monday (Asia/Ho_Chi_Minh):
nix and npm; monthly: GitHub Actions. Each PR is one targeted update.

### Auto-merge (GitHub-native)

`.github/workflows/dependabot-auto-merge.yml` asks GitHub to
squash-auto-merge every eligible Dependabot version-update PR:

- author is exactly `dependabot[bot]`, base is the repository default
  branch, repository is exactly `linhnt89/nixos-config` (drafts are
  skipped until they become ready);
- the workflow uses the trusted base-branch form
  (`pull_request_target`) but never checks out, executes, or evaluates
  pull-request code — it only runs the GitHub CLI preinstalled on the
  hosted runner to request `gh pr merge --auto --squash`. It never
  merges directly and never approves reviews;
- GitHub's repository auto-merge setting and any branch-protection
  rules remain authoritative: **one-time prerequisite** — enable
  "Allow auto-merge" in repository settings (Settings → General →
  Pull Requests) for auto-merge to work at all.

**Consequence:** with no required checks on this repository (local
validation is authoritative; CI is an optional `workflow_dispatch`
fallback, not a required check), an eligible bot PR may merge promptly
without a local `scripts/check.sh` run. If required checks are
configured later, GitHub enforces them before auto-merging. The
workflow is covered by `scripts/test-dependabot-automerge.sh`
(actionlint + parsed-YAML meaning assertions), part of the static
checks in `scripts/check.sh`.

Review checklist for Dependabot PRs that are NOT auto-merged (e.g.
human-created or retargeted ones, or once required checks exist), and
for the post-merge machine verification of every update PR:

1. Local validation passes: `scripts/check.sh` (static checks +
   `nix flake check` + non-activating toplevel build). CI is an
   optional fallback, not required.
2. The diff touches only the intended input (`flake.lock`, possibly
   `flake.nix` for ref rewrites) or the intended npm pins.
3. `nixpkgs-unstable` PRs: confirm the Pi package change is wanted.

Dependabot does not touch the shared Firstmate toolchain pins — those are
nixdev-config-owned (see the lanes table above). No other bot runs — do
not add Renovate or a second PR automation, and do not let the scheduled
staleness job open PRs.

## Staleness reporting

`scripts/check-stale.sh` reports stale inputs and tool pins. It is
read-only: no mutations, no PRs, no lock writes.

```bash
scripts/check-stale.sh                # text table; exit 1 if anything is stale
scripts/check-stale.sh --json         # machine-readable
scripts/check-stale.sh --days 30      # looser age threshold
scripts/check-stale.sh --skip-remote  # offline: age analysis only
```

The `stale` CI job runs it weekly (Monday 06:30) and on manual
`workflow_dispatch` — the only scheduled CI job. A red weekly run is
the report — the table is in the job summary. It never opens PRs
(Dependabot owns those) and never builds or activates the system.

## Local validation (authoritative)

`scripts/check.sh` is the repository-owned local gate for ordinary
changes. It runs static checks (shell syntax, YAML/JSON parsing,
regression suites incl. `scripts/test-dependabot-automerge.sh`), `nix
flake check`, and a non-activating toplevel build — it never switches,
tests, or activates the system. Run it on the branch before merging any
human-authored PR, and before the post-merge machine verification of
any update PR (eligible Dependabot PRs auto-merge without it):

```bash
scripts/check.sh                        # local gate (sudo build)
scripts/check.sh --nix-build-only       # plain `nix build` (no sudo; CI/containers)
scripts/check.sh --skip-build           # static checks + flake check only
```

CI is an optional fallback for an independent clean-run build: the
`build` job is `workflow_dispatch`-only and runs the same
`scripts/check.sh --nix-build-only`. A green CI run is not required
and does not replace local validation or the post-merge machine
verification in the next section. Eligible Dependabot PRs are
auto-merged by GitHub (see "Dependabot") — they may land without a
local run, which is exactly why the post-merge verification below is
authoritative for what actually runs on the machine.

## Targeted manual updates

```bash
# Stable lane (one coherent diff):
nix flake update nixpkgs

# Pi lane only:
nix flake update nixpkgs-unstable

# nixdev-config (public input; fetches without any GitHub access-token):
nix flake lock --update-input nixdev-config

# Shared Firstmate toolchain pins (treehouse/herdr/no-mistakes/axi):
# owned by nixdev-config — bump there, then re-pin nixdev-config and
# rebuild. This repo has no local pins for them anymore.
```

After any lock change, commit `flake.lock` together with the change —
never a bare lock refresh. Feature branches validate with
`scripts/check.sh` (its build step uses `sudo nixos-rebuild build
--flake .#metacube`) per `AGENTS.md`.

## Automated nixdev-config bump (trusted-dependency lane)

`scripts/update-nixdev-config.sh` is the narrow operator-invoked
automation for ONE input: `nixdev-config`. After (or to detect) a
merged change in `linhnt89/nixdev-config`, it re-pins that input to the
upstream default-branch head, validates the resulting configuration
locally, opens a lock-only PR through `gh-axi`, squash-merges it only
after every guard passes, and fast-forwards the canonical local `main`.
It **never switches, tests, boots, or otherwise activates the machine**
— activation stays a separate explicit command (below).

This is an alternative to the normal per-input Dependabot PR for this
one public input; it is deliberately NOT used for any other lane. Every
ordinary NixOS change keeps the existing workflow: branch, edit, run
`scripts/check.sh`, open a normal PR, switch only after approval.

```bash
scripts/update-nixdev-config.sh            # inspect-only plan + optional confirm
scripts/update-nixdev-config.sh --help     # usage
scripts/update-nixdev-config.sh --dry-run  # full preflight + exact plan; changes nothing
scripts/update-nixdev-config.sh --yes      # unattended run (automation; stdin is not a TTY)
```

What the run does, in order:

1. **Preconditions (guarded; it refuses instead of stash/reset/clean/force-push):**
   - the canonical checkout (default: `$HOME/firstmate/projects/nixos-config`;
     override with `NIXDEV_UPDATE_CANONICAL_REPO`; portable git-worktree
     discovery is the last-resort fallback) must be on `main` and
     completely clean;
   - `git fetch origin main` must succeed and local `main` must equal
     `origin/main` (a conflict-free, fast-forwardable starting point);
   - `gh-axi` must be installed, authenticated, and able to read the
     `linhnt89/nixos-config` repository (proves the GitHub path);
   - if the lock already sits at the upstream head it exits 0 with
     "already up to date" — no branch, no PR.
2. Resolves the upstream default-branch head from the sibling
   `nixdev-config` source checkout (default:
   `$HOME/firstmate/projects/nixdev-config`; override with
   `NIXDEV_UPDATE_NIXDEV_SRC`) via a read-only `git ls-remote origin
   HEAD` (the sibling is never modified). If only the *default* sibling
   is absent or stale, the gh-axi API lookup is used instead; a missing
   or unusable *explicit* `NIXDEV_UPDATE_NIXDEV_SRC` refuses the run.
   Re-pins only the input: `nix flake lock --update-input nixdev-config`
   on a dedicated branch (`deps/nixdev-config-bump-<rev8>`).
3. **Proves the scope** with a structured `flake.lock` comparison
   (jq node graph): only nodes reachable exclusively from the
   nixdev-config subtree may change; the root input map, lock version,
   and every other input's lock entry (including shared nodes) must be
   byte-identical, and the new rev must equal the upstream head. It
   refuses on anything broader or on a no-op.
4. Commits ONLY `flake.lock` and runs the repository's authoritative
   local gate `scripts/check.sh` (static checks + `nix flake check` +
   non-activating toplevel build + Home Manager user-config evaluation).
5. Pushes the branch (never force), opens the PR via `gh-axi`
   (`chore(deps): bump nixdev-config input to <rev8>`), verifies PR
   identity/head against the validated commit, and squash-merges
   (`--squash --delete-branch`) only after identity + mergeability pass.
6. After a **confirmed** merge (API-verified, tree equal to the validated
   commit), fast-forwards the canonical local `main` and deletes the
   temporary branch, leaving the checkout clean.

Refusals and failures always leave work inspectable: the branch stays
checked out in the canonical checkout, any pushed branch/PR stays on
GitHub, and the script prints exactly what happened and what to inspect.
GitHub outages are retried a few times; a sustained outage stops the run
with a clear error — it never claims success it cannot verify.

Env overrides (offline/testing only, except the canonical repo): see the
script header. In particular `NIXDEV_UPDATE_CHECK_FLAGS` forwards extra
arguments to `check.sh` (e.g. `--skip-build` in constrained
environments) and `NIXDEV_UPDATE_TARGET_REV` pins an explicit rev
instead of the upstream head.

Paths and precedence (portable on every machine; no hardcoded home paths):

| role | default | override |
| --- | --- | --- |
| canonical `nixos-config` checkout | `$HOME/firstmate/projects/nixos-config` | `NIXDEV_UPDATE_CANONICAL_REPO` |
| sibling `nixdev-config` source checkout | `$HOME/firstmate/projects/nixdev-config` | `NIXDEV_UPDATE_NIXDEV_SRC` |

An explicit override always beats a `$HOME` default. The canonical
`$HOME` default is checked before the last-resort portable git-worktree
discovery. The upstream head is resolved from the sibling source
checkout first; a missing/stale *default* sibling falls back to the
gh-axi API, while a missing or unusable *explicit*
`NIXDEV_UPDATE_NIXDEV_SRC` refuses the run before any mutation.

Regression tests for the guards run as part of `scripts/check.sh`:
`scripts/test-update-nixdev-config.sh` is fully offline (fake gh-axi/
nix/check.sh, local bare origin) and covers dirty-tree refusal, lock-
scope refusal, validation failure, PR identity mismatch, merge failure,
GitHub outage handling, PR discovery from both the reported gh-axi
`api_response: body: ""` no-match envelope and a genuine numeric open PR,
plus refusal of nonnumeric PR output and the no-activation guarantee. The
updater treats only a positive decimal PR number as an existing PR or as
safe input to identity, state, URL, and merge checks.

## From merged update to a running system

Real desktop/system-use validation happens here, on the machine,
after merge — local checks and CI only prove the configuration builds.
Activation is **manual and post-merge only**, and only from the
canonical checkout:

1. **Refresh the canonical checkout.** `~/nixos-config` (the clone Pi
   reads) must be on a clean `main` before building. Fetch and
   fast-forward only; never `git clean` or hard-reset it — it holds
   runtime-owned files (`home/pi/settings.json` is seeded from it once).
   If it is dirty, reconcile the local edits before touching anything.
2. **Build** (does not activate):
   ```bash
   cd ~/nixos-config
   sudo nixos-rebuild build --flake .#metacube
   ```
3. **Verify** before switching:
   ```bash
   systemctl --failed
   systemctl --user --failed
   no-mistakes doctor
   ```
   and the tool-version checks below, plus anything specific to the
   change (e.g. `hyprctl configerrors` after desktop changes).
4. **Switch only after explicit approval** (captain/firstmate):
   ```bash
   sudo nixos-rebuild switch --flake .#metacube
   ```
   CI and the staleness report never switch, and never run this step.

After a shared-toolchain bump that lands through a nixdev-config update
(e.g. a no-mistakes bump), **firstmate restarts the shared
no-mistakes daemon** (the systemd user unit points at the old store
path until then; after ~14 days the old path would be GC'd, breaking
the unit). Crewmates never restart the daemon — it is one instance
serving every lane. Same rule for any tool whose running service reads
the Nix store path (e.g. herdr sessions).

## Tool-version checks

```bash
no-mistakes doctor                       # daemon + gate validation
no-mistakes --version                    # vs firstmate NO_MISTAKES_MIN (fm-bootstrap.sh)
gh-axi --version && chrome-devtools-axi --version
lavish-axi --version && tasks-axi --version && quota-axi --version
herdr --version && treehouse --version && pi --version
```

`no-mistakes --version` may print its own update banner; the Nix
install is updated via nixdev-config's pins, not `no-mistakes update`.
If the banner is noise, `NO_MISTAKES_NO_UPDATE_CHECK=1` suppresses the
background check. The nixdev-config pins must stay above firstmate's
floor constants (see `fm-bootstrap.sh`); check that after every
nixdev-config update and after every npm pin bump there.

## Rollback

```bash
sudo nixos-rebuild switch --rollback     # back to the previous generation
```

Or pick a previous generation from the systemd-boot menu at boot.
Because every update is its own generation, a bad bump is reverted by
switching back — another reason update PRs stay per-input and locally
build-verified. Rollback never touches `stateVersion`.

## Separate update paths (not this repo)

- **Firstmate itself**: git-level fast-forward update via
  `/updatefirstmate` → `bin/fm-update.sh`. Independent of Nix; keep the
  npm pins above the new floor constants afterwards.
- **Pi**: packaged by `nixpkgs-unstable`; bumped through the Pi lane.
  `pi update` is for non-Nix installs. Pi's runtime data
  (`~/.pi/agent/…`) is outside Git — see `docs/pi-settings-boundary.md`.
- **Herdr / Treehouse / no-mistakes / the axi CLIs**: Nix-managed via
  nixdev-config's firstmateTools pins; their self-update commands are
  documented but not used here.

## NixOS branch migration (26.11)

NixOS 26.05 is supported until 2026-12-31. Moving to 26.11 ("Zokor",
expected ~Nov 2026) is a deliberate event, not a routine bump:

1. Edit refs: `nixpkgs` → `nixos-26.11`, `home-manager` →
   `release-26.11`, and `templates/dev/flake.nix`.
2. Read `rl-2611` release notes for module changes.
3. Build-verify per branch as usual, switch only after approval.
4. **Keep `stateVersion` at `26.05`.**
