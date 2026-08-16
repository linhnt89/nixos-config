#!/usr/bin/env bash
#
# check-stale.sh — report stale flake inputs and tool pins.
#
# Read-only: parses flake.lock and home/firstmate/node-tools/package.json.
# It never modifies the repository, never opens PRs or issues, and never
# runs nix commands that write the lock. Network lookups use the GitHub
# API and npm view, and degrade to "unresolved" instead of failing the
# whole check.
#
# Usage:
#   scripts/check-stale.sh [--days N] [--json] [--skip-remote]
#
#   --days N       staleness threshold in days (default 14)
#   --json         print one JSON object instead of the text table
#   --skip-remote  skip network lookups; locked-age and local pin
#                  analysis only
#
# What counts as stale:
#   * a flake input whose locked revision is older than --days days
#     ("old") and/or behind its upstream branch head ("behind")
#   * the noMistakes tarball pin older than --days days or behind the
#     latest stable release (prereleases are never considered "latest")
#   * an npm tool pin behind the latest published version
#
# Exit codes: 0 = up to date, 1 = at least one stale item, 2 = usage or
# input error.
#
# Env overrides (offline/testing only):
#   NO_MISTAKES_LATEST_STABLE=1.48.0     skip the GitHub API lookup
#   CHECK_STALE_NPM_LATEST="a=1.0,b=2.0" skip npm view (comma-separated
#                                        name=version pairs)
#   GH_TOKEN=<token>                     GitHub API auth (CI passes
#                                        ${{ github.token }}; locally
#                                        unauthenticated is fine)
#
# See docs/updates-runbook.md for how to act on the results.

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
lock="$repo_root/flake.lock"
package_json="$repo_root/home/firstmate/node-tools/package.json"

days=14
json=0
skip_remote=0

usage() {
  cat <<'EOF'
Usage: scripts/check-stale.sh [--days N] [--json] [--skip-remote]

Report stale flake inputs and tool pins without modifying anything.
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

# newer A B -> true when A is a strictly higher version than B.
newer() {
  [[ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" == "$1" && "$1" != "$2" ]]
}

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

# no_mistakes_latest_stable -> latest non-prerelease release tag
# (without the leading "v"), via the GitHub releases API.
no_mistakes_latest_stable() {
  local tag
  tag="$(
    curl -fsSL \
      'https://api.github.com/repos/kunchenguid/no-mistakes/releases/latest' \
      2>/dev/null | jq -r '.tag_name // empty' || true
  )"
  printf '%s' "${tag#v}"
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
# e.g. the root "nixpkgs" input points at node "nixpkgs_2" (the 26.05
# lane), while node "nixpkgs" itself is herdr's internal input.
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

    tarball)
      url="$(jq -r --arg n "$node" '.nodes[$n].locked.url // ""' "$lock")"
      pinned=""
      if [[ "$url" =~ /download/v([0-9]+\.[0-9]+\.[0-9]+)/ ]]; then
        pinned="${BASH_REMATCH[1]}"
      fi
      [[ -n "$pinned" ]] || status="unknown"

      upstream=""
      if [[ -n "${NO_MISTAKES_LATEST_STABLE:-}" ]]; then
        upstream="${NO_MISTAKES_LATEST_STABLE#v}"
      elif [[ "$skip_remote" == 0 ]]; then
        upstream="$(no_mistakes_latest_stable || true)"
      fi
      if [[ -n "$upstream" && -n "$pinned" && "$upstream" != "$pinned" ]]; then
        if newer "$upstream" "$pinned"; then
          if [[ "$status" == "old" ]]; then status="old,behind"; else status="behind"; fi
        fi
      fi
      emit_row no-mistakes "$key" "$pinned" "$upstream" "$age_json" "$status" \
        "tarball pin; bump via scripts/update-no-mistakes.sh"
      ;;

    none)
      notes+=("input '$key': no locked entry in flake.lock")
      ;;

    *)
      notes+=("input '$key': unsupported lock type '$locked_type'")
      ;;
  esac
done < <(jq -r '.nodes.root.inputs | to_entries[] | [.key, .value] | @tsv' "$lock")

# --- npm tool pins --------------------------------------------------------
if [[ -f "$package_json" ]]; then
  while IFS=$'\t' read -r name pinned; do
    [[ -n "$name" ]] || continue
    upstream=""
    if [[ -n "${CHECK_STALE_NPM_LATEST:-}" ]]; then
      upstream="$(
        printf '%s' "$CHECK_STALE_NPM_LATEST" | tr ',' '\n' \
          | awk -F= -v p="$name" '$1 == p {print $2; exit}'
      )"
    elif [[ "$skip_remote" == 0 ]]; then
      upstream="$(
        npm view --no-audit --no-fund --fetch-timeout=15000 --fetch-retries=1 \
          "$name" version 2>/dev/null || true
      )"
    fi
    status="ok"
    if [[ -n "$upstream" && -n "$pinned" && "$upstream" != "$pinned" ]]; then
      if newer "$upstream" "$pinned"; then
        status="behind"
      fi
    fi
    emit_row npm "$name" "$pinned" "$upstream" null "$status" ""
  done < <(jq -r '.dependencies | to_entries[] | [.key, .value] | @tsv' "$package_json")
else
  notes+=("package.json not found at $package_json; skipping npm pins")
fi

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
printf 'no-mistakes (tarball pin):\n'
jq -sr '.[] | select(.kind == "no-mistakes")
  | [.name, .pinned, (.upstream // "-"), (.age_days // "-"), .status]
  | @tsv' "$rows" \
  | awk -F'\t' '{printf "  %-18s pinned %-8s latest %-8s age %-4s %-11s\n", $1, $2, $3, $4, toupper($5)}'
printf 'node tools (home/firstmate/node-tools):\n'
jq -sr '.[] | select(.kind == "npm")
  | [.name, .pinned, (.upstream // "-"), .status]
  | @tsv' "$rows" \
  | awk -F'\t' '{printf "  %-18s pinned %-8s latest %-8s %s\n", $1, $2, $3, toupper($4)}'
if ((${#notes[@]} > 0)); then
  printf 'Notes:\n'
  for n in "${notes[@]}"; do
    printf '  - %s\n' "$n"
  done
fi
if [[ "$stale" == 1 ]]; then
  printf 'Result: STALE - at least one input or tool pin is behind\n'
else
  printf 'Result: up to date\n'
fi
exit "$stale"
