#!/usr/bin/env bash
#
# update-no-mistakes.sh — bump the noMistakes tarball input in flake.nix
# to a stable release and refresh the lock entry.
#
# Dependabot's nix ecosystem cannot update tarball-URL inputs, so this
# helper owns that one pin. It only touches flake.nix (the release URL)
# and flake.lock (via `nix flake lock --update-input noMistakes`).
#
# Usage:
#   scripts/update-no-mistakes.sh [version] [--dry-run] [--skip-lock]
#
#   version      explicit stable version, with or without a leading "v"
#                (e.g. "1.48.0" or "v1.48.0"). Default: latest stable
#                release from the GitHub releases API (prereleases are
#                never selected, even when they carry plain tags).
#   --dry-run    print what would change without modifying anything.
#   --skip-lock  update flake.nix only; do not run `nix flake lock`
#                (used for testing or when locking separately).
#
# Safety refusals:
#   * malformed or prerelease versions (e.g. "1.48", "latest", "1.49.0-rc.1")
#   * versions below the firstmate floor NO_MISTAKES_MIN (default 1.31.2,
#     the constant in firstmate's fm-bootstrap.sh)
#   * downgrades below the currently pinned version
#   * an unrecognized noMistakes URL shape in flake.nix
#   * running while flake.nix has uncommitted changes (skipped outside
#     a git repository)
#
# Env overrides (offline/testing only):
#   NO_MISTAKES_LATEST_STABLE=1.48.0   skip the GitHub API lookup
#   NO_MISTAKES_MIN=1.31.2             firstmate floor
#
# After merge: rebuild, verify, switch (see docs/updates-runbook.md),
# then FIRSTMATE restarts the no-mistakes daemon. Never run
# `no-mistakes update` on this host — the binary is Nix-managed.

set -euo pipefail
export GIT_TERMINAL_PROMPT=0

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
flake="$repo_root/flake.nix"

dry_run=0
skip_lock=0
version_arg=""

die() {
  echo "error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: scripts/update-no-mistakes.sh [version] [--dry-run] [--skip-lock]

Bump the noMistakes tarball input in flake.nix to a stable release and
refresh the lock entry. See the script header for safety rules.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    --skip-lock) skip_lock=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) die "unknown option: $1" ;;
    *)
      [[ -z "$version_arg" ]] || die "unexpected extra argument: $1"
      version_arg="$1"
      shift
      ;;
  esac
done

# normalize_version STR -> prints STR with a leading "v" stripped after
# verifying it is a plain stable X.Y.Z triple (no prerelease suffixes).
normalize_version() {
  local v="${1#v}"
  [[ "$v" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s' "$v"
}

# newer A B -> true when A is a strictly higher version than B.
newer() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" && "$1" != "$2" ]]
}

# latest_stable_tag -> latest non-prerelease release tag (vX.Y.Z).
# Uses the GitHub releases API: `releases/latest` honors the release
# metadata, so prereleases with plain tags (e.g. v1.52.0) are excluded.
latest_stable_tag() {
  local tag
  tag="$(
    curl -fsSL \
      'https://api.github.com/repos/kunchenguid/no-mistakes/releases/latest' \
      2>/dev/null | jq -r '.tag_name // empty' || true
  )"
  [[ -n "$tag" ]] || die "could not determine the latest stable no-mistakes release (network?)"
  printf '%s' "$tag"
}

[[ -f "$flake" ]] || die "flake.nix not found at $flake"

current_url="$(grep -oE 'https://github\.com/kunchenguid/no-mistakes/releases/download/[^"]+' "$flake" | head -n1 || true)"
[[ -n "$current_url" ]] || die "could not find the noMistakes URL in flake.nix"

url_re='^https://github\.com/kunchenguid/no-mistakes/releases/download/v([0-9]+\.[0-9]+\.[0-9]+)/no-mistakes-v([0-9]+\.[0-9]+\.[0-9]+)-linux-amd64\.tar\.gz$'
if [[ "$current_url" =~ $url_re ]]; then
  current="${BASH_REMATCH[1]}"
  [[ "${BASH_REMATCH[2]}" == "$current" ]] \
    || die "noMistakes URL is inconsistent (download version != archive version): $current_url"
else
  die "unrecognized noMistakes URL; refusing to guess how to bump it: $current_url"
fi

if [[ -n "$version_arg" ]]; then
  target_source="$version_arg"
elif [[ -n "${NO_MISTAKES_LATEST_STABLE:-}" ]]; then
  target_source="$NO_MISTAKES_LATEST_STABLE"
else
  target_source="$(latest_stable_tag)"
fi

target="$(normalize_version "$target_source")" \
  || die "invalid version '$target_source' (expected a stable vX.Y.Z, e.g. 1.48.0)"

floor="${NO_MISTAKES_MIN:-1.31.2}" # firstmate fm-bootstrap.sh NO_MISTAKES_MIN
newer "$floor" "$target" && die "version $target is below the firstmate floor ($floor); refusing"

if [[ "$target" == "$current" ]]; then
  echo "no-mistakes is already pinned at v$current; nothing to do"
  exit 0
fi

newer "$current" "$target" && die "refusing to downgrade no-mistakes from v$current to v$target"

new_url="https://github.com/kunchenguid/no-mistakes/releases/download/v${target}/no-mistakes-v${target}-linux-amd64.tar.gz"

if [[ "$dry_run" == 1 ]]; then
  echo "dry-run: would update the flake.nix no-mistakes pin v$current -> v$target"
  echo "  - $current_url"
  echo "  + $new_url"
  exit 0
fi

if git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1 \
  && ! git -C "$repo_root" diff --quiet -- flake.nix; then
  die "flake.nix has uncommitted changes; commit or stash them first"
fi

sed -i "s|$current_url|$new_url|" "$flake"
grep -qF "$new_url" "$flake" || die "failed to update the URL in flake.nix"
echo "updated flake.nix: no-mistakes v$current -> v$target"

if [[ "$skip_lock" == 1 ]]; then
  echo "skipped lock refresh (--skip-lock); run: nix flake lock --update-input noMistakes"
  exit 0
fi

(cd "$repo_root" && nix flake lock --update-input noMistakes)
grep -qF "$new_url" "$repo_root/flake.lock" \
  || die "flake.lock was not refreshed for $new_url"
echo "lock entry refreshed:"
jq -r '.nodes.noMistakes.locked | "  url:          \(.url)\n  narHash:      \(.narHash)\n  lastModified: \(.lastModified)"' \
  "$repo_root/flake.lock"
