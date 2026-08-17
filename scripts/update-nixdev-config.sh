#!/usr/bin/env bash
#
# update-nixdev-config.sh — narrow trusted-dependency automation for the
# `nixdev-config` flake input of nixos-config.
#
# After (or to detect) a merged change in the public linhnt89/nixdev-config
# flake, this operator-invoked script:
#
#   1. verifies preconditions: clean canonical `main` checkout, reachable
#      authenticated GitHub path (gh-axi), and a conflict-free
#      fast-forwardable starting point;
#   2. re-pins ONLY the nixdev-config input
#      (`nix flake lock --update-input nixdev-config`) and PROVES via a
#      structured flake.lock comparison (jq node-graph, node reachability)
#      that no other input, source file, module, setting, or lock entry
#      changed, refusing when the scope is broader or not fast-forwardable;
#   3. runs the repository's authoritative local validation
#      (scripts/check.sh) on the dedicated branch; failures leave the
#      branch and PR inspectable, never hidden or discarded;
#   4. commits only the lock update, pushes the branch (never force),
#      opens the PR through gh-axi, verifies PR identity/head against the
#      validated commit, and merges it with squash only after every guard
#      passes;
#   5. after a CONFIRMED merge, fast-forwards the canonical local `main`
#      and leaves it clean.
#
# This script NEVER runs an activation command (no switch/test/boot/
# activate; no systemctl/swaymsg/hyprctl reloads). Activation remains a
# separate explicit operator command after the merged result is present
# locally; the script prints those exact commands at the end. Every
# ordinary (non-nixdev-config) NixOS change keeps the existing PR flow.
#
# Usage:
#   scripts/update-nixdev-config.sh [--dry-run] [--yes] [-h|--help]
#
#   --dry-run  inspect-only: run the preflight guards, resolve the upstream
#              head, print the exact plan (branch name, commands, PR title/
#              body, validation and post-merge steps). Modifies nothing
#              except git remote-tracking refs (the preflight fetch).
#   --yes      skip the interactive confirmation; required when stdin is
#              not a TTY (automation). All safety guards still apply.
#   -h|--help  show usage.
#
# Preconditions (guards refuse; the script never stashes, cleans, resets,
# force-pushes, or overwrites unlanded work):
#   * the canonical checkout exists, is on the base branch (`main`), and is
#     completely clean (no staged, unstaged, or untracked changes);
#   * `git fetch origin <base>` succeeds and local <base> equals
#     origin/<base> (conflict-free, fast-forwardable starting point);
#   * gh-axi is installed, authenticated, and can read the private
#     linhnt89/nixos-config repository (proves the GitHub path);
#   * the lock is not already at the upstream default-branch head
#     ("already up to date" -> exit 0, no branch, no PR).
#
# Env overrides (offline/testing only, except CANONICAL_REPO):
#   NIXDEV_UPDATE_CANONICAL_REPO   canonical checkout path (default: the
#                                  main worktree of the git repo this
#                                  script is invoked from, discovered
#                                  portably - no hardcoded home paths)
#   NIXDEV_UPDATE_BASE_REF         base branch (default: main)
#   NIXDEV_UPDATE_GH_AXI_BIN       gh-axi binary (default: gh-axi)
#   NIXDEV_UPDATE_NIX_BIN          nix binary (default: nix)
#   NIXDEV_UPDATE_CHECK_BIN        validation script (default:
#                                  scripts/check.sh inside the canonical
#                                  checkout; run with cwd=canonical)
#   NIXDEV_UPDATE_CHECK_FLAGS      extra args for the validation script
#                                  (default: none = full authoritative
#                                  gate; tests use --skip-build or none)
#   NIXDEV_UPDATE_TARGET_REV       skip the upstream-head lookup and
#                                  re-pin to this explicit rev
#                                  (testing/advanced use)
#   NIXDEV_UPDATE_RETRIES          transient-failure retries (default 4)
#   NIXDEV_UPDATE_RETRY_DELAY      delay between retries, seconds (default 4)
#   NIXDEV_UPDATE_POLL_TRIES       merge/identity poll iterations (default 12)
#   NIXDEV_UPDATE_POLL_DELAY       delay between polls, seconds (default 5)

set -euo pipefail
export GIT_TERMINAL_PROMPT=0

script_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

dry_run=0
assume_yes=0
test_guard=""
TEST_GUARD_ARGS=()

DIE() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: scripts/update-nixdev-config.sh [--dry-run] [--yes] [-h|--help]

Narrow trusted-dependency automation: bump ONLY the `nixdev-config`
flake input to the upstream default-branch head, validate locally,
open and squash-merge a lock-only PR via gh-axi, then fast-forward the
canonical local main. Never switches or activates the machine.

  --dry-run   inspect-only plan (preflight + exact commands), no changes
  --yes       skip the interactive confirmation (automation)
  -h, --help  show this help

Preconditions: clean canonical main checkout, reachable authenticated
GitHub path (gh-axi), fast-forwardable start. See the script header and
docs/updates-runbook.md ("Automated nixdev-config bump") for details.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --yes) assume_yes=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --test-guard)
      # Offline test entrypoint: run one guard function in the caller's
      # fixture environment. Dispatched after function definitions below.
      # Env-only inputs; never touches GitHub.
      test_guard=1
      shift
      TEST_GUARD_ARGS=("$@")
      break
      ;;
    *) DIE "unknown option: $1 (try --help)" ;;
  esac
done

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# parse_body — extract the `body:` value of gh-axi's TOON envelope, or pass
# through raw scalar output (gh-axi prints numeric jq results raw, e.g. PR
# numbers), because that is not enveloped.
parse_body() {
  local out
  out="$(cat)"
  if grep -q '^api_response:' <<<"$out"; then
    sed -n 's/^[[:space:]]*body:[[:space:]]*//p' <<<"$out" | head -n 1
  else
    printf '%s' "$out" | sed 's/[[:space:]]*$//'
  fi
}

# is_transient_err TEXT -> true when a gh-axi failure looks like a GitHub
# outage or rate limit instead of a hard error (auth/validation/404).
is_transient_err() {
  [[ "$1" =~ 'HTTP 5' || "$1" =~ 'No server is currently available'
     || "$1" =~ 'rate limit' || "$1" =~ 'timed out' || "$1" =~ 'timeout' ]]
}

GH_AXI_BIN="${NIXDEV_UPDATE_GH_AXI_BIN:-gh-axi}"
NIX_BIN="${NIXDEV_UPDATE_NIX_BIN:-nix}"
REPO_RETRIES="${NIXDEV_UPDATE_RETRIES:-4}"
RETRY_DELAY="${NIXDEV_UPDATE_RETRY_DELAY:-4}"
POLL_TRIES="${NIXDEV_UPDATE_POLL_TRIES:-12}"
POLL_DELAY="${NIXDEV_UPDATE_POLL_DELAY:-5}"

# gh_api_scalar PATH JQ_EXPR -> prints one scalar from the authenticated
# gh-axi API path; retries transient (outage/ratelimit) failures and treats
# hard errors (auth, not-found) as terminal. Nonzero exit on failure.
gh_api_scalar() {
  local path="$1" expr="$2" i out rc
  for ((i = 1; i <= REPO_RETRIES; i++)); do
    if out="$("$GH_AXI_BIN" api "$path" --jq "$expr" 2>&1)"; then
      parse_body <<<"$out"
      return 0
    fi
    rc=$?
    if ! is_transient_err "$out"; then
      echo "gh-axi api failed (non-transient): $out" >&2
      return 2
    fi
    if [[ $i -lt REPO_RETRIES ]]; then
      echo "gh-axi api transient failure ($out); retrying in ${RETRY_DELAY}s..." >&2
      sleep "$RETRY_DELAY"
    fi
  done
  echo "gh-axi api unreachable after ${REPO_RETRIES} attempts: $out" >&2
  return 1
}

# ---------------------------------------------------------------------------
# canonical checkout discovery and preflight guards
# ---------------------------------------------------------------------------

# resolve_canonical -> absolute path of the canonical main checkout: the
# main worktree of the git repo this script is invoked from, or the
# explicit NIXDEV_UPDATE_CANONICAL_REPO override. No hardcoded home paths.
resolve_canonical() {
  if [[ -n "${NIXDEV_UPDATE_CANONICAL_REPO:-}" ]]; then
    printf '%s' "$(cd -- "$NIXDEV_UPDATE_CANONICAL_REPO" && pwd -P)"
    return 0
  fi
  local common
  common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [[ -n "$common" && -d "$common" ]] || return 1
  printf '%s' "$(cd -- "$(dirname -- "$common")" && pwd -P)"
}

# guard_canonical_clean CANONICAL BASE_REF -> 0 when the canonical checkout
# is a real worktree on BASE_REF with a completely clean working tree.
guard_canonical_clean() {
  local canon="$1" base="$2" branch status
  git -C "$canon" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "canonical checkout is not a git working tree: $canon"; return 1; }
  [[ "$(git -C "$canon" rev-parse --is-bare-repository)" == "false" ]] \
    || { echo "canonical checkout is bare: $canon"; return 1; }
  branch="$(git -C "$canon" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ "$branch" == "$base" ]] \
    || { echo "canonical checkout is not on $base (on '$branch')"; return 1; }
  git -C "$canon" rev-parse -q --verify MERGE_HEAD >/dev/null 2>&1 \
    && { echo "canonical checkout has a merge in progress"; return 1; }
  git -C "$canon" rev-parse -q --verify CHERRY_PICK_HEAD >/dev/null 2>&1 \
    && { echo "canonical checkout has a cherry-pick in progress"; return 1; }
  git -C "$canon" rev-parse -q --verify REVERT_HEAD >/dev/null 2>&1 \
    && { echo "canonical checkout has a revert in progress"; return 1; }
  status="$(git -C "$canon" status --porcelain)"
  [[ -z "$status" ]] || {
    echo "canonical checkout is dirty; refusing to touch it:"
    printf '%s\n' "$status" | sed 's/^/    /'
    echo "reconcile or commit that work first; nothing was stashed, reset, or deleted."
    return 1
  }
  return 0
}

# guard_ff_start CANONICAL BASE_REF BASE_SHA -> fetch origin and require
# local BASE_REF == origin/BASE_REF == BASE_SHA (a conflict-free,
# fast-forwardable, reviewed starting point).
guard_ff_start() {
  local canon="$1" base="$2" base_sha="$3" local_sha origin_sha
  if ! git -C "$canon" fetch origin "$base" 2>"/tmp/nixdev-bump-fetch.$$"; then
    cat "/tmp/nixdev-bump-fetch.$$" >&2 || true
    rm -f "/tmp/nixdev-bump-fetch.$$" 2>/dev/null || true
    echo "error: could not fetch origin/$base (network or credentials)." >&2
    return 1
  fi
  rm -f "/tmp/nixdev-bump-fetch.$$" 2>/dev/null || true
  local_sha="$(git -C "$canon" rev-parse "$base")"
  origin_sha="$(git -C "$canon" rev-parse "origin/$base" 2>/dev/null || true)"
  [[ -n "$origin_sha" && "$local_sha" == "$origin_sha" && "$local_sha" == "$base_sha" ]] || {
    echo "canonical $base ($local_sha) is not at origin/$base ($origin_sha);" >&2
    echo "the starting point is not conflict-free/fast-forwardable. reconcile manually, then re-run." >&2
    return 1
  }
  return 0
}

# github_repo_from_url URL -> OWNER/REPO for github.com https remotes.
github_repo_from_url() {
  sed -n 's#^https://github\.com/\([^/]*\)/\([^/]*\)\(\.git\)\?$#\1/\2#p' <<<"$1" \
    | sed 's/\.git$//'
}

# ---------------------------------------------------------------------------
# lock scope analysis
# ---------------------------------------------------------------------------

# reachable_nodes LOCKFILE STARTNODE -> the set of lock nodes reachable from
# STARTNODE through the input graph, one per line. Handles string input
# values (a node name) and array values (a path rooted at root.inputs).
reachable_nodes() {
  local lock="$1" start="$2"
  local seen="" frontier="$start" n next deps d
  while [[ -n "$frontier" ]]; do
    next=""
    while read -r n; do
      [[ -n "$n" ]] || continue
      case " $seen " in
        *" $n "*) continue ;;
      esac
      seen="$seen $n"
      deps="$(jq -cr --arg n "$n" '
        . as $l
        | def pr($p):
            if ($p | length) == 1 then $l.nodes.root.inputs[$p[0]]
            else
              ($l.nodes.root.inputs[$p[0]] as $f
               | reduce $p[1:][] as $seg ($f;
                   if ($l.nodes[.].inputs[$seg] | type) == "string"
                   then $l.nodes[.].inputs[$seg]
                   else . end))
            end;
        $l.nodes[$n].inputs // {} | to_entries[] | .value
        | if type == "string" then . else pr(.) end
        | select(. != null)
      ' "$lock" 2>/dev/null || true)"
      while read -r d; do
        [[ -n "$d" ]] || continue
        case " $seen $next " in
          *" $d "*) ;;
          *) next="$next $d" ;;
        esac
      done <<<"$deps"
    done <<<"$frontier"
    frontier="${next# }"
  done
  printf '%s\n' $seen
}

# lock_scope_check OLD NEW TARGET_REV -> 0 when the only differences between
# the two locks are confined to nodes reachable exclusively from the
# nixdev-config subtree (in EITHER lock, so node additions/removals count),
# the root input map and lock version are unchanged, and the new
# nixdev-config rev equals TARGET_REV. Prints one reason on failure.
lock_scope_check() {
  local old="$1" new="$2" target="$3"
  jq -e . "$old" >/dev/null 2>&1 || { echo "old flake.lock is not valid JSON"; return 1; }
  jq -e . "$new" >/dev/null 2>&1 || { echo "new flake.lock is not valid JSON"; return 1; }

  [[ "$(jq -r '.version' "$old")" == "$(jq -r '.version' "$new")" ]] \
    || { echo "lock version changed"; return 1; }
  [[ "$(jq -cS '.nodes.root' "$old")" == "$(jq -cS '.nodes.root' "$new")" ]] \
    || { echo "root input map changed"; return 1; }

  local nd nd_old nd_new
  nd="$(jq -r '.nodes.root.inputs["nixdev-config"] // empty' "$new")"
  [[ -n "$nd" ]] || { echo "nixdev-config input missing from new lock"; return 1; }
  nd_old="$(jq -r --arg n "$nd" '.nodes[$n].locked.rev // empty' "$old" 2>/dev/null || true)"
  nd_new="$(jq -r --arg n "$nd" '.nodes[$n].locked.rev // empty' "$new" 2>/dev/null || true)"
  [[ -n "$nd_old" ]] || { echo "nixdev-config node missing from old lock"; return 1; }
  [[ -n "$nd_new" ]] || { echo "nixdev-config node missing from new lock"; return 1; }
  [[ "$nd_new" != "$nd_old" ]] || { echo "nixdev-config rev did not change (already up to date)"; return 1; }
  [[ "$nd_new" == "$target" ]] || {
    echo "nixdev-config new rev $nd_new != upstream target $target"; return 1
  }

  # allowed-to-change: nodes reachable from nixdev-config in either lock,
  # minus nodes reachable from any other root input (shared nodes must not
  # move).
  local allowed others roam name o room names n1 n2
  allowed="$( { reachable_nodes "$old" "$nd"; reachable_nodes "$new" "$nd"; } | sort -u )"
  others=""
  while read -r name; do
    [[ -n "$name" && "$name" != "nixdev-config" ]] || continue
    o="$(jq -r --arg k "$name" '.nodes.root.inputs[$k] // empty' "$new")"
    [[ -n "$o" ]] || continue
    others="$others
$( { reachable_nodes "$old" "$o"; reachable_nodes "$new" "$o"; } | sort -u )"
  done < <(jq -r '.nodes.root.inputs | keys[]' "$new")

  roam="$(printf '%s\n' "$allowed" | grep -vxF -f <(printf '%s\n' $others) || true)"
  names="$( { jq -r '.nodes | keys[]' "$old"; jq -r '.nodes | keys[]' "$new"; } | sort -u )"
  while read -r name; do
    [[ -n "$name" ]] || continue
    if printf '%s\n' "$roam" | grep -qxF "$name"; then
      continue
    fi
    n1="$(jq -cS --arg n "$name" '.nodes[$n] // "absent"' "$old")"
    n2="$(jq -cS --arg n "$name" '.nodes[$n] // "absent"' "$new")"
    [[ "$n1" == "$n2" ]] || {
      echo "lock scope violated: node '$name' changed outside the nixdev-config subtree"; return 1
    }
  done <<<"$names"
  return 0
}

# ---------------------------------------------------------------------------
# flow steps
# ---------------------------------------------------------------------------

# update_lock CANONICAL -> re-pin only the nixdev-config input.
update_lock() {
  (cd "$1" && "$NIX_BIN" flake lock --update-input nixdev-config)
}

# guard_commit_scope CANONICAL -> the (pre-commit) working-tree change must
# be exactly the flake.lock modification, nothing else.
guard_commit_scope() {
  local canon="$1" status mods other
  status="$(git -C "$canon" status --porcelain)"
  mods="$(grep -c '^ M flake\.lock$' <<<"$status" || true)"
  other="$(grep -vc '^ M flake\.lock$' <<<"$status" || true)"
  if [[ "$mods" != "1" || "$other" != "0" ]]; then
    echo "unexpected working-tree changes after the lock update; refusing to commit:"
    printf '%s\n' "$status" | sed 's/^/    /'
    return 1
  fi
  return 0
}

# run_validation CANONICAL -> the repository's authoritative local gate.
run_validation() {
  local canon="$1"
  local check_bin="${NIXDEV_UPDATE_CHECK_BIN:-$canon/scripts/check.sh}"
  echo "==> running $check_bin ${NIXDEV_UPDATE_CHECK_FLAGS:-} (cwd=$canon)"
  (cd "$canon" && "$check_bin" ${NIXDEV_UPDATE_CHECK_FLAGS:-})
}

# verify_pr_identity PR_NUM VALIDATED_SHA -> poll the PR API until
# state=open, base/head refs match, head.sha == the validated commit, and
# mergeability was computed (true = mergeable; false = refusing).
verify_pr_identity() {
  local num="$1" validated="$2" i state base headref headsha mergeable
  for ((i = 1; i <= POLL_TRIES; i++)); do
    state="$(gh_api_scalar "/repos/$REPO/pulls/$num" '.state' || return 1)"
    base="$(gh_api_scalar "/repos/$REPO/pulls/$num" '.base.ref' || return 1)"
    headref="$(gh_api_scalar "/repos/$REPO/pulls/$num" '.head.ref' || return 1)"
    headsha="$(gh_api_scalar "/repos/$REPO/pulls/$num" '.head.sha' || return 1)"
    mergeable="$(gh_api_scalar "/repos/$REPO/pulls/$num" '.mergeable' || true)"
    [[ "$state" == "open" ]] || { echo "PR #$num is not open (state=$state); refusing to merge" >&2; return 1; }
    [[ "$base" == "$BASE_REF" && "$headref" == "$BRANCH" ]] \
      || { echo "PR refs mismatch ($base <- $headref); refusing to merge" >&2; return 1; }
    [[ "$headsha" == "$validated" ]] || {
      echo "PR head $headsha != validated commit $validated; refusing to merge" >&2; return 1
    }
    [[ "$mergeable" == "false" ]] && {
      echo "PR #$num is not mergeable (conflicts or blocked); refusing to merge" >&2; return 1
    }
    [[ "$mergeable" == "true" ]] && return 0
    [[ $i -lt POLL_TRIES ]] && { echo "mergeability not yet computed; polling..." >&2; sleep "$POLL_DELAY"; }
  done
  echo "PR #$num mergeability never computed after ${POLL_TRIES} polls" >&2
  return 1
}

# confirm_merged PR_NUM -> after a merge attempt (ours, or one whose
# response was lost in an outage), poll until the API reports the PR merged,
# then ensure the merged commit is present locally and print it. Never
# claims success without this confirmation.
confirm_merged() {
  local num="$1" i merged msha
  for ((i = 1; i <= POLL_TRIES; i++)); do
    merged="$(gh_api_scalar "/repos/$REPO/pulls/$num" '.merged' || true)"
    if [[ "$merged" == "true" ]]; then
      msha="$(gh_api_scalar "/repos/$REPO/pulls/$num" '.merge_commit_sha' || true)"
      [[ -n "$msha" && "$msha" != "null" ]] || {
        echo "PR #$num merged but merge_commit_sha is empty" >&2; return 1
      }
      if ! git -C "$CANON" cat-file -e "$msha^{commit}" 2>/dev/null; then
        echo "merged commit $msha not present locally; fetching origin..." >&2
        git -C "$CANON" fetch origin "$BASE_REF" || { echo "fetch failed; cannot verify merged commit locally" >&2; return 1; }
      fi
      git -C "$CANON" cat-file -e "$msha^{commit}" 2>/dev/null || {
        echo "merged commit $msha still unavailable locally" >&2; return 1
      }
      echo "$msha"
      return 0
    fi
    [[ $i -lt POLL_TRIES ]] && { echo "merge not yet confirmed; polling..." >&2; sleep "$POLL_DELAY"; }
  done
  echo "PR #$num was not confirmed merged after ${POLL_TRIES} polls" >&2
  return 1
}

# ---------------------------------------------------------------------------
# test entrypoints (offline)
# ---------------------------------------------------------------------------

guard_dispatch() {
  case "${1:-}" in
    clean)
      local canon="${NIXDEV_UPDATE_CANONICAL_REPO:-}"
      [[ -n "$canon" ]] || { echo "clean guard: NIXDEV_UPDATE_CANONICAL_REPO required" >&2; exit 1; }
      guard_canonical_clean "$canon" "${NIXDEV_UPDATE_BASE_REF:-main}"
      ;;
    lock-scope)
      [[ $# -eq 4 ]] || { echo "lock-scope guard: OLD NEW TARGET required" >&2; exit 1; }
      lock_scope_check "$2" "$3" "$4"
      ;;
    no-activation)
      # The activation instructions live ONLY inside the quoted heredoc
      # starting with this delimiter; strip it and require that the rest of
      # the script never invokes an activation or destructive command.
      local body
      body="$(sed -n '/^cat <<'"'"'NIXOS_ACTIVATION_RUNBOOK_README'"'"'$/,/^NIXOS_ACTIVATION_RUNBOOK_README$/d' "$script_path/update-nixdev-config.sh")"
      # Patterns use a character-class break so the guard never matches its
      # own definitions below.
      local forbidden=(
        'nixos-rebuild switc[h]' 'nixos-rebuild tes[t]' 'nixos-rebuild boo[t]'
        'nixos-rebuild activat[e]' 'nixos-rebuild.*-[-]switch'
        'systemct[l]' 'swayms[g]' 'hyprct[l]' 'nixos-test-drive[r]'
        'git stas[h]' 'git clea[n]' 'git reset -[-]hard' 'git checkout -[-] '
        'push -[-]force' 'push -[f]' '-[-]force-with-lease' '-[-]force'
      )
      local f
      for f in "${forbidden[@]}"; do
        grep -nE "$f" <<<"$body" >/dev/null 2>&1 && {
          echo "no-activation guard failed: forbidden pattern '$f' in executable body" >&2
          return 1
        }
      done
      echo "no-activation guard: executable body contains no activation or destructive commands" >&2
      return 0
      ;;
    *)
      echo "unknown test guard: ${1:-}" >&2
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# main flow
# ---------------------------------------------------------------------------

if [[ -n "$test_guard" ]]; then
  guard_dispatch "${TEST_GUARD_ARGS[@]}"
  exit $?
fi

LOCK_BEFORE=""
LOCK_AFTER=""
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$LOCK_BEFORE" "$LOCK_AFTER"' EXIT

CANON="$(resolve_canonical)" \
  || DIE "cannot resolve the canonical checkout (run inside a nixos-config worktree, or set NIXDEV_UPDATE_CANONICAL_REPO)"
BASE_REF="${NIXDEV_UPDATE_BASE_REF:-main}"
OWNER=""
REPO=""
echo "canonical checkout: $CANON (base: $BASE_REF)"

guard_canonical_clean "$CANON" "$BASE_REF" || DIE "preconditions not met"

BASE_SHA="$(git -C "$CANON" rev-parse "$BASE_REF")"
guard_ff_start "$CANON" "$BASE_REF" "$BASE_SHA" || DIE "starting point is not fast-forwardable"

origin_url="$(git -C "$CANON" config --get remote.origin.url 2>/dev/null || true)"
REPO="$(github_repo_from_url "$origin_url")"
[[ -n "$REPO" ]] || DIE "origin is not a github.com https remote: $origin_url"
OWNER="${REPO%/*}"

echo "==> checking the GitHub path (gh-axi, authenticated)"
gh_api_scalar "/repos/$REPO" '.full_name' >/dev/null \
  || DIE "gh-axi cannot read $REPO; check installation/authentication (the repo is private)"

LOCK="$CANON/flake.lock"
[[ -f "$LOCK" ]] || DIE "flake.lock not found at $LOCK"

if [[ -n "${NIXDEV_UPDATE_TARGET_REV:-}" ]]; then
  TARGET_REV="$NIXDEV_UPDATE_TARGET_REV"
  echo "==> target rev from NIXDEV_UPDATE_TARGET_REV: $TARGET_REV"
else
  TARGET_REV="$(gh_api_scalar "/repos/linhnt89/nixdev-config/commits/HEAD" '.sha')" \
    || DIE "could not resolve the upstream nixdev-config head"
fi
[[ "$TARGET_REV" =~ ^[0-9a-f]{40}$ ]] || DIE "unusable upstream target rev: '$TARGET_REV'"

ND_NODE="$(jq -r '.nodes.root.inputs["nixdev-config"] // empty' "$LOCK")"
CURRENT_REV="$(jq -r --arg n "$ND_NODE" '.nodes[$n].locked.rev // empty' "$LOCK" 2>/dev/null || true)"
echo "nixdev-config: locked $CURRENT_REV -> upstream head $TARGET_REV"

if [[ "$CURRENT_REV" == "$TARGET_REV" ]]; then
  echo "already up to date: the nixdev-config lock is at the upstream default-branch head."
  echo "nothing to do; no branch, no PR."
  exit 0
fi

BRANCH="deps/nixdev-config-bump-${TARGET_REV:0:8}"
TITLE="chore(deps): bump nixdev-config input to ${TARGET_REV:0:8}"

echo
echo "==> plan"
echo "  branch:   $BRANCH"
echo "  commit:   $TITLE"
echo "  change:   flake.lock nixdev-config $CURRENT_REV -> $TARGET_REV (lock-only)"
echo "  validate: scripts/check.sh (static checks + nix flake check + non-activating toplevel build + Home Manager eval)"
echo "  github:   push $BRANCH -> PR -> squash-merge (gh-axi); then fast-forward $CANON $BASE_REF"
echo "  never:    no activation, no switch, no stash/reset/clean/force-push"

if [[ "$dry_run" == 1 ]]; then
  echo
  echo "[dry-run] the above is a plan only; nothing was modified (only the preflight fetch updated remote-tracking refs)."
  echo "[dry-run] to execute: scripts/update-nixdev-config.sh --yes"
  exit 0
fi

if [[ "$assume_yes" != 1 ]]; then
  [[ -t 0 ]] || DIE "stdin is not a TTY and --yes was not passed; refusing to proceed unattended"
  read -r -p "proceed with the plan above? [y/N] " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "aborted."; exit 1; }
fi

git -C "$CANON" rev-parse -q --verify "refs/heads/$BRANCH" >/dev/null 2>&1 \
  && DIE "branch $BRANCH already exists; a previous run may have failed - inspect and clean it up first"

echo "==> creating branch $BRANCH"
git -C "$CANON" checkout -q -b "$BRANCH" "$BASE_REF"

LOCK_BEFORE="$(mktemp)"
cp "$LOCK" "$LOCK_BEFORE"

echo "==> re-pinning the nixdev-config input (lock update)"
if ! update_lock "$CANON"; then
  git -C "$CANON" checkout -q "$BASE_REF"
  cp "$LOCK_BEFORE" "$LOCK"
  DIE "nix flake lock --update-input nixdev-config failed; the lock refresh (our own intermediate change) was reverted and canonical was left on $BASE_REF"
fi
LOCK_AFTER="$(mktemp)"
cp "$LOCK" "$LOCK_AFTER"

echo "==> proving the lock scope (structured comparison)"
if ! lock_scope_check "$LOCK_BEFORE" "$LOCK_AFTER" "$TARGET_REV"; then
  git -C "$CANON" checkout -q "$BASE_REF"
  cp "$LOCK_BEFORE" "$LOCK"
  DIE "lock update out of scope or not fast-forwardable: restored the previous lock and left canonical on $BASE_REF"
fi
echo "    ok: only the nixdev-config subtree moved ($CURRENT_REV -> $TARGET_REV)"

guard_commit_scope "$CANON" || {
  git -C "$CANON" checkout -q "$BASE_REF"
  cp "$LOCK_BEFORE" "$LOCK"
  DIE "working-tree scope check failed: restored the previous lock and left canonical on $BASE_REF"
}

echo "==> committing the lock-only change"
git -C "$CANON" add flake.lock
git -C "$CANON" commit -q -m "$TITLE"
COMMIT_FILES="$(git -C "$CANON" show --pretty=format: --name-only HEAD | sed '/^$/d')"
[[ "$COMMIT_FILES" == "flake.lock" ]] || {
  echo "error: commit touched unexpected files:" >&2; printf '%s\n' "$COMMIT_FILES" >&2; exit 1
}
git -C "$CANON" diff --quiet "$BASE_REF" HEAD -- flake.nix \
  || { echo "error: flake.nix changed; refusing to continue" >&2; exit 1; }
VALIDATED_SHA="$(git -C "$CANON" rev-parse HEAD)"

echo "==> running the authoritative local validation (never activates)"
if ! run_validation "$CANON"; then
  echo "validation FAILED on branch $BRANCH (commit $VALIDATED_SHA)." >&2
  echo "the branch is left checked out and inspectable in $CANON; nothing was pushed." >&2
  echo "inspect with:  git -C '$CANON' log --oneline $BASE_REF..HEAD" >&2
  exit 1
fi

echo "==> pushing $BRANCH (never force)"
if ! git -C "$CANON" push origin "HEAD:$BRANCH" 2>&1 | sed 's/^/    /'; then
  echo "push failed; the branch and commit remain inspectable in $CANON." >&2
  exit 1
fi

printf '%s\n' \
"re-pins the \`nixdev-config\` flake input from \`$CURRENT_REV\` to \`$TARGET_REV\` (upstream default-branch head).

Automated narrow lock bump via \`scripts/update-nixdev-config.sh\`:

- Structured \`flake.lock\` comparison proved the change is confined to the nixdev-config subtree; no other input, source file, module, setting, or lock entry changed.
- Validated with \`scripts/check.sh\` (static checks + \`nix flake check\` + non-activating toplevel build + Home Manager user-config evaluation). Nothing was switched or activated.
- After merge, fast-forward the canonical checkout and build/verify/switch manually per \`docs/updates-runbook.md\`; this lane never activates the machine.
- Rollback: \`git revert\` this merge, or use the dedicated rollback step in \`docs/updates-runbook.md\` (never run by this lane)." > "$BODY_FILE"

echo "==> opening the PR via gh-axi"
PR_NUM="$(gh_api_scalar "/repos/$REPO/pulls?state=open&head=$OWNER:$BRANCH" '.[0].number // empty' || true)"
if [[ -n "$PR_NUM" ]]; then
  echo "reusing existing open PR #$PR_NUM for branch $BRANCH"
else
  if ! "$GH_AXI_BIN" pr create --repo "$REPO" --title "$TITLE" --body-file "$BODY_FILE" --base "$BASE_REF" --head "$BRANCH"; then
    PR_NUM="$(gh_api_scalar "/repos/$REPO/pulls?state=open&head=$OWNER:$BRANCH" '.[0].number // empty' || true)"
    [[ -n "$PR_NUM" ]] || {
      echo "error: gh-axi pr create failed and no PR exists for $BRANCH (the branch is pushed to origin)." >&2
      echo "create the PR manually, then re-run after the result is merged, or inspect the branch in $CANON." >&2
      exit 1
    }
    echo "warning: pr create reported a transient error, but PR #$PR_NUM exists; continuing."
  else
    PR_NUM="$(gh_api_scalar "/repos/$REPO/pulls?state=open&head=$OWNER:$BRANCH" '.[0].number // empty')"
    [[ -n "$PR_NUM" ]] || DIE "PR was created but its number could not be resolved"
  fi
fi
PR_URL="https://github.com/$REPO/pull/$PR_NUM"
echo "PR: $PR_URL"

echo "==> verifying PR identity/head against the validated commit"
verify_pr_identity "$PR_NUM" "$VALIDATED_SHA" \
  || DIE "PR identity check failed; PR $PR_URL is left open and inspectable"

echo "==> merging PR #$PR_NUM (squash, per repo convention)"
if ! "$GH_AXI_BIN" pr merge "$PR_NUM" --repo "$REPO" --squash --delete-branch; then
  echo "warning: gh-axi pr merge reported an error; confirming the actual state via the API..." >&2
fi
if ! MERGED_SHA="$(confirm_merged "$PR_NUM")"; then
  echo "error: PR #$PR_NUM was not confirmed merged." >&2
  echo "the PR (if still open) is left inspectable at $PR_URL; nothing was fast-forwarded." >&2
  exit 1
fi
echo "confirmed merged: $MERGED_SHA"

echo "==> verifying merged identity (tree == validated commit tree)"
[[ "$(git -C "$CANON" rev-parse "$VALIDATED_SHA^{tree}")" == "$(git -C "$CANON" rev-parse "$MERGED_SHA^{tree}")" ]] || {
  echo "error: merged tree != validated tree; refusing to fast-forward" >&2
  echo "inspect the merge at $PR_URL" >&2
  exit 1
}

LOCAL_MAIN="$(git -C "$CANON" rev-parse "$BASE_REF")"
[[ "$LOCAL_MAIN" == "$BASE_SHA" ]] || {
  echo "error: canonical $BASE_REF moved during the run (was $BASE_SHA, now $LOCAL_MAIN); refusing to fast-forward" >&2
  exit 1
}
git -C "$CANON" fetch origin "$BASE_REF"
ORIGIN_MAIN="$(git -C "$CANON" rev-parse "origin/$BASE_REF")"
if [[ "$ORIGIN_MAIN" != "$MERGED_SHA" ]]; then
  echo "error: origin/$BASE_REF ($ORIGIN_MAIN) is not the merged commit ($MERGED_SHA);" >&2
  echo "another change landed in between - out of this lane's narrow scope." >&2
  echo "canonical $BASE_REF was NOT touched; fast-forward it manually with a plain: git pull --ff-only" >&2
  exit 1
fi
git -C "$CANON" rev-parse -q --verify "$MERGED_SHA^" >/dev/null 2>&1 || {
  echo "error: merged commit $MERGED_SHA is not a normal single-parent commit; refusing to fast-forward" >&2
  exit 1
}
[[ "$(git -C "$CANON" rev-parse "$MERGED_SHA^")" == "$BASE_SHA" ]] || {
  echo "error: merged commit $MERGED_SHA does not sit directly on $BASE_SHA;" >&2
  echo "the base moved mid-run - out of this lane's narrow scope. fast-forward manually: git pull --ff-only" >&2
  exit 1
}

echo "==> fast-forwarding canonical $BASE_REF"
git -C "$CANON" switch -q "$BASE_REF"
git -C "$CANON" merge --ff-only "$MERGED_SHA"
git -C "$CANON" branch -q -D "$BRANCH"

rm -f "$BODY_FILE" "$LOCK_BEFORE" "$LOCK_AFTER"
trap - EXIT

STILL_DIRTY="$(git -C "$CANON" status --porcelain)"
[[ -z "$STILL_DIRTY" ]] || {
  echo "error: canonical checkout is not clean after fast-forward:" >&2
  printf '%s\n' "$STILL_DIRTY" >&2
  exit 1
}

echo
echo "DONE: nixdev-config $CURRENT_REV -> $TARGET_REV merged via $PR_URL"
echo "canonical $CANON is on $BASE_REF at $MERGED_SHA (clean) - the merged result is present locally."
echo
echo "The machine was NOT switched or activated (this lane never activates)."
echo "Building, verifying, and switching remain separate explicit commands:"
cat <<'NIXOS_ACTIVATION_RUNBOOK_README'
  # 1. build (does not activate):
  cd <canonical checkout>
  sudo nixos-rebuild build --flake .#metacube
  # 2. verify before any switch:
  systemctl --failed && systemctl --user --failed
  no-mistakes doctor
  # 3. switch ONLY after explicit approval (captain/firstmate), per docs/updates-runbook.md:
  sudo nixos-rebuild switch --flake .#metacube
NIXOS_ACTIVATION_RUNBOOK_README
echo "See docs/updates-runbook.md ('Automated nixdev-config bump') for the full procedure."