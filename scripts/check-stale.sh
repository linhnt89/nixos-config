#!/usr/bin/env bash
#
# check-stale.sh — report stale flake inputs.
#
# Read-only: parses flake.lock. It never modifies the repository, never
# opens PRs or issues, and never runs nix commands that write the lock.
# Network lookups use the GitHub API and degrade to "unresolved" instead
# of failing the whole check.
#
# Usage:
#   scripts/check-stale.sh [--days N] [--json] [--skip-remote]
#
#   --days N       staleness threshold in days (default 14)
#   --json         print one JSON object instead of the text table
#   --skip-remote  skip network lookups; locked-age analysis only
#
# What counts as stale:
#   * a flake input whose locked revision is older than --days days
#     ("old") and/or behind its upstream branch head ("behind")
#
# Exit codes: 0 = up to date, 1 = at least one stale item, 2 = usage or
# input error.
#
# Env overrides (offline/testing only):
#   GH_TOKEN=<token>                     GitHub API auth (CI passes
#                                        ${{ github.token }}; locally
#                                        unauthenticated is fine)
#
# Shared Firstmate toolchain pins (no-mistakes, herdr, treehouse, the
# axi CLIs) are nixdev-config-owned since the firstmateTools refactor;
# their freshness is tracked in linhnt89/nixdev-config, not here. See
# docs/updates-runbook.md for how to act on the results.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
lock="$repo_root/flake.lock"

days=14
json=0
skip_remote=0

usage() {
  cat <<'EOF'
Usage: scripts/check-stale.sh [--days N] [--json] [--skip-remote]

Report stale flake inputs without modifying anything.
See the script header for details.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --days) days="${2:-}"; shift 2 ;;
    --json) json=1; shift ;;
    --skip-remote) skip_remote=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

[[ "$days" =~ ^[0-9]+$ && "$days" -gt 0 ]] || {
  echo "error: --days must be a positive integer" >&2
  exit 2
}

[[ -f "$lock" ]] || {
  echo "error: flake.lock not found at $lock" >&2
  exit 2
}

now="$(date +%s)"
rows="$(mktemp)"
trap 'rm -f "$rows"' EXIT

# gh_api_commit_sha OWNER REPO REF -> 40-char sha of the ref head.
# Uses the GitHub API: fast even for nixpkgs, where `git ls-remote`
# has to download a huge ref advertisement.
gh_api_commit_sha() {
  local owner="$1" repo="$2" ref="$3"
  local auth=()
  [[ -n "${GH_TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $GH_TOKEN")
  curl -fsSL "${auth[@]}" \
    "https://api.github.com/repos/$owner/$repo/commits/$ref" 2>/dev/null \
    | jq -r '.sha // empty' || true
}

# emit_row KIND NAME PINNED UPSTREAM AGE_JSON STATUS NOTE -> one JSON row
emit_row() {
  jq -nc \
    --arg kind "$1" --arg name "$2" --arg pinned "$3" --arg upstream "$4" \
    --argjson age "${5:-null}" --arg status "$6" --arg note "$7" \
    '{kind: $kind, name: $name, pinned: $pinned, upstream: $upstream,
      age_days: $age, status: $status, note: $note}' >>"$rows"
}

notes=()

# --- flake inputs ---------------------------------------------------------
#
# root.inputs maps each input name to a lock node name. The values matter:
# e.g. the root "nixpkgs" input points at node "nixpkgs" (the 26.05
# lane) while nixpkgs-unstable is its own node.
while IFS=$'\t' read -r key node; do
  [[ -n "$key" ]] || continue

  locked_type="$(jq -r --arg n "$node" '.nodes[$n].locked.type // "none"' "$lock")"
  last_modified="$(jq -r --arg n "$node" '.nodes[$n].locked.lastModified // 0' "$lock")"

  age=""
  age_json=null
  if [[ "$last_modified" != "0" ]]; then
    age=$(( (now - last_modified) / 86400 ))
    age_json="$age"
  fi

  status="ok"
  if [[ -n "$age" && "$age" -gt "$days" ]]; then
    status="old"
  fi

  case "$locked_type" in
    github)
      owner="$(jq -r --arg n "$node" '.nodes[$n].locked.owner // ""' "$lock")"
      repo="$(jq -r --arg n "$node" '.nodes[$n].locked.repo // ""' "$lock")"
      rev="$(jq -r --arg n "$node" '.nodes[$n].locked.rev // ""' "$lock")"
      ref="$(jq -r --arg n "$node" '.nodes[$n].original.ref // ""' "$lock")"
      pinned="${rev:0:8}"
      [[ -n "$pinned" ]] || status="unknown"

      upstream=""
      note=""
      if [[ "$ref" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # Tag-pinned input (e.g. herdr v0.8.0): only detect a moved tag.
        note="tag-pinned"
      fi
      if [[ "$skip_remote" == 0 ]]; then
        # Branch, tag, or default-branch input: compare against the ref
        # head. The API dereferences annotated tags (verified on herdr).
        branch="$ref"
        [[ -n "$branch" ]] || branch="HEAD"
        upstream="$(gh_api_commit_sha "$owner" "$repo" "$branch" || true)"
        if [[ -n "$upstream" ]]; then
          upstream="${upstream:0:8}"
          [[ "$upstream" == "$pinned" ]] || {
            if [[ "$status" == "old" ]]; then status="old,behind"; else status="behind"; fi
          }
        fi
      fi
      emit_row flake "$key" "$pinned" "$upstream" "$age_json" "$status" "$note"
      ;;

    none)
      notes+=("input '$key': no locked entry in flake.lock")
      ;;

    *)
      notes+=("input '$key': unsupported lock type '$locked_type'")
      ;;
  esac
done < <(jq -r '.nodes.root.inputs | to_entries[] | [.key, .value] | @tsv' "$lock")

# --- report ---------------------------------------------------------------
stale=0
if jq -se 'any(.[]; .status != "ok")' "$rows" >/dev/null 2>&1; then
  stale=1
fi

if [[ "$json" == 1 ]]; then
  jq -s \
    --arg generated "$(date '+%Y-%m-%d %H:%M:%S %z')" \
    --argjson days "$days" \
    --argjson stale "$stale" \
    --argjson notes "$(jq -nc --argjson n "$(printf '%s\n' "${notes[@]:-}" | jq -Rsc 'split("\n")[:-1]')" '$n')" \
    '{generated_at: $generated, days: $days, stale: $stale, notes: $notes, rows: .}' \
    "$rows"
  exit "$stale"
fi

printf 'Staleness report (%s), threshold %d days\n' "$(date '+%Y-%m-%d %H:%M')" "$days"
printf 'Flake inputs:\n'
jq -sr '.[] | select(.kind == "flake")
  | [.name, .pinned, (.upstream // "-"), (.age_days // "-"), .status, (.note // "")]
  | @tsv' "$rows" \
  | awk -F'\t' '{printf "  %-18s pinned %-8s upstream %-8s age %-4s %-11s %s\n", $1, $2, $3, $4, toupper($5), $6}'
if ((${#notes[@]} > 0)); then
  printf 'Notes:\n'
  for n in "${notes[@]}"; do
    printf '  - %s\n' "$n"
  done
fi
if [[ "$stale" == 1 ]]; then
  printf 'Result: STALE - at least one flake input is behind\n'
else
  printf 'Result: up to date\n'
fi
exit "$stale"
