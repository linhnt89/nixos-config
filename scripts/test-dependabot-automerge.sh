#!/usr/bin/env bash
#
# test-dependabot-automerge.sh — focused regression tests for the
# GitHub-native Dependabot auto-merge workflow
# (.github/workflows/dependabot-auto-merge.yml).
#
# Locks in the workflow's MEANING, not its spelling:
#   A. actionlint (or an equivalent semantic lint) parses every
#      .github/workflows/*.yml — triggers, expressions, permissions.
#   B. Parsed-YAML structure assertions (never raw grep of the file):
#      1. triggered by pull_request_target (trusted base-branch form)
#         with a restricted type list that includes opened/synchronize
#         and excludes closed (no pointless runs after merge/close);
#      2. the job condition restricts to dependabot[bot] PRs whose base
#         is the repository default branch, in exactly
#         linhnt89/nixos-config, and skips drafts (GitHub cannot
#         auto-merge drafts; ready_for_review picks them up later);
#      3. permissions include pull-requests: write and contents: write
#         (the documented set for enabling auto-merge);
#      4. the job has NO `uses:` step — no checkout, no third-party
#         action, so pull-request code is never checked out or executed;
#      5. the single step requests SQUASH AUTO-MERGE only
#         (gh pr merge --auto --squash) — never a direct merge
#         (--merge/--rebase absent) and never an approval (no gh pr
#         approve, no reviews permission).
#
# No system build, no flake evaluation, no activation. Runs offline when
# the tools are present; falls back to `nix shell` like scripts/check.sh;
# warns and skips the parts whose tools are unavailable.
#
# Usage: scripts/test-dependabot-automerge.sh
# Exit:  0 = all checks passed (or everything skipped); 1 = one failed.

set -u

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
wf="$repo_root/.github/workflows/dependabot-auto-merge.yml"

failures=0

fail() {
  failures=$((failures + 1))
  echo "FAIL  $*" >&2
}

pass() {
  echo "PASS  $*"
}

[[ -f "$wf" ]] || {
  echo "FAIL  $wf not found" >&2
  exit 1
}

# --- A. actionlint (semantic workflow lint) -------------------------------

echo '== actionlint'

actionlint_bin=""
if command -v actionlint >/dev/null 2>&1; then
  actionlint_bin="actionlint"
elif command -v nix >/dev/null 2>&1; then
  actionlint_bin="nix-shell-actionlint"
fi

case "$actionlint_bin" in
  actionlint)
    if actionlint "$repo_root"/.github/workflows/*.yml; then
      pass "actionlint: .github/workflows/*.yml is valid"
    else
      fail "actionlint: .github/workflows/*.yml has errors"
    fi
    ;;
  nix-shell-actionlint)
    if nix shell nixpkgs#actionlint -c bash -c 'actionlint "$@"' _ \
      "$repo_root"/.github/workflows/*.yml; then
      pass "actionlint (via nix shell): .github/workflows/*.yml is valid"
    else
      fail "actionlint (via nix shell): .github/workflows/*.yml has errors"
    fi
    ;;
  *)
    echo "warn  actionlint unavailable (no actionlint, no nix); skipping" >&2
    ;;
esac

# --- B. parsed-YAML structure assertions ----------------------------------

echo '== parsed-YAML meaning assertions'

# Parser selection mirrors scripts/check.sh: python3+PyYAML, else yq,
# else `nix shell nixpkgs#yq-go`; skip with a warning if none exists.
yaml_parser=""
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  yaml_parser="python3"
elif command -v yq >/dev/null 2>&1; then
  yaml_parser="yq"
elif command -v nix >/dev/null 2>&1; then
  yaml_parser="nix-shell-yq"
fi

if [[ -z "$yaml_parser" ]]; then
  echo "warn  no YAML parser available (python3/PyYAML, yq, or nix); skipping assertions" >&2
else
  run_yaml() {
    # run_yaml <expr> — evaluates a small yq-compatible expression
    # against $wf (one value per line).
    case "$yaml_parser" in
      python3)
        python3 - "$wf" "$1" <<'EOF'
import sys, re, yaml

with open(sys.argv[1]) as fh:
    data = yaml.safe_load(fh)
# PyYAML (YAML 1.1) parses the `on` key as boolean True; normalize it.
if isinstance(data, dict) and True in data and 'on' not in data:
    data['on'] = data.pop(True)
expr = sys.argv[2]

def walk(node, seg):
    """Evaluate one pipeline segment against a list of nodes."""
    seg = seg.strip()
    # '.[]' (iteration) must be checked before the path branch below,
    # which also starts with '.'. After that, plain ops do not collide
    # with paths and can stay after it.
    if seg == '.[]':
        out = []
        for n in node:
            if isinstance(n, list):
                out.extend(n)
            else:
                out.append(n)
        return out
    if seg.startswith('.'):
        cur = node
        for part in seg[1:].split('.'):
            m = re.match(r'^(.*?)(?:\[(\d*)\])?$', part)
            name = m.group(1).strip('"')
            idx = m.group(2)
            nxt = []
            for n in cur:
                if not (isinstance(n, dict) and name in n):
                    continue
                v = n[name]
                if idx is not None:
                    if idx == '':
                        if isinstance(v, list):
                            nxt.extend(v)
                    elif isinstance(v, list) and int(idx) < len(v):
                        nxt.append(v[int(idx)])
                else:
                    nxt.append(v)
            cur = nxt
        return cur
    if seg == 'keys':
        out = []
        for n in node:
            if isinstance(n, dict):
                out.extend(n.keys())
        return out
    m = re.match(r'^has\("([^"]*)"\)$', seg)
    if m:
        return [isinstance(n, dict) and m.group(1) in n for n in node]
    if seg == 'length':
        return [len(n) for n in node]
    return []

nodes = [data]
for seg in expr.split('|'):
    nodes = walk(nodes, seg)
for n in nodes:
    if isinstance(n, bool):
        print('true' if n else 'false')
    elif n is not None:
        print(n)
EOF
        ;;
      yq)
        yq -r "$1" "$wf"
        ;;
      nix-shell-yq)
        nix shell nixpkgs#yq-go -c yq -r "$1" "$wf"
        ;;
    esac
  }

  # 1. Trigger: pull_request_target with restricted types, no `closed`.
  triggers="$(run_yaml '.on | keys | .[]')"
  if printf '%s\n' "$triggers" | grep -qx 'pull_request_target'; then
    pass "trigger is pull_request_target (trusted base-branch form)"
  else
    fail "trigger is not pull_request_target (got: $triggers)"
  fi
  if printf '%s\n' "$triggers" | grep -q '^pull_request$'; then
    fail "plain pull_request trigger present (PR code context would run)"
  else
    pass "no plain pull_request trigger"
  fi
  types="$(run_yaml '.on."pull_request_target".types | .[]')"
  if printf '%s\n' "$types" | grep -qx 'opened' &&
    printf '%s\n' "$types" | grep -qx 'synchronize'; then
    pass "types include opened + synchronize"
  else
    fail "types missing opened/synchronize (got: ${types//$'\n'/ })"
  fi
  if printf '%s\n' "$types" | grep -qx 'closed'; then
    fail "types include closed (workflow would run after merge/close)"
  else
    pass "types exclude closed"
  fi

  # 2. Job condition: dependabot[bot] author, default-branch base,
  #    exact repository, non-draft.
  if_expr="$(run_yaml '.jobs.dependabot.if')"
  for guard in \
    "dependabot[bot]" \
    "github.event.pull_request.base.ref" \
    "github.event.repository.default_branch" \
    "linhnt89/nixos-config" \
    "github.event.pull_request.draft"; do
    if [[ "$if_expr" == *"$guard"* ]]; then
      pass "job condition guards $guard"
    else
      fail "job condition missing guard: $guard"
    fi
  done

  # 3. Permissions: documented auto-merge set.
  if [[ "$(run_yaml '.permissions."pull-requests"')" == "write" ]]; then
    pass "permissions: pull-requests: write"
  else
    fail "permissions: pull-requests is not write"
  fi
  if [[ "$(run_yaml '.permissions.contents')" == "write" ]]; then
    pass "permissions: contents: write"
  else
    fail "permissions: contents is not write"
  fi

  # 4. No `uses:` step anywhere in the job (no checkout, no actions).
  uses="$(run_yaml '.jobs.dependabot.steps[] | has("uses")' | grep -v '^false$' || true)"
  if [[ -z "$uses" ]]; then
    pass "no uses: steps (pull-request code is never checked out or executed)"
  else
    fail "job has uses: steps: $uses"
  fi

  # 5. The single run step: squash auto-merge only, no direct merge,
  #    no approval.
  n_steps="$(run_yaml '.jobs.dependabot.steps | length')"
  if [[ "$n_steps" == "1" ]]; then
    pass "job has exactly one step"
  else
    fail "job has $n_steps steps (expected 1)"
  fi
  run_cmd="$(run_yaml '.jobs.dependabot.steps[0].run')"
  if [[ "$run_cmd" == *"gh pr merge"* && "$run_cmd" == *"--auto"* ]]; then
    pass "step requests auto-merge (gh pr merge --auto)"
  else
    fail "step does not request auto-merge: $run_cmd"
  fi
  if [[ "$run_cmd" == *"--squash"* ]]; then
    pass "auto-merge uses squash method"
  else
    fail "auto-merge does not use --squash: $run_cmd"
  fi
  if [[ "$run_cmd" != *"--merge"* && "$run_cmd" != *"--rebase"* && "$run_cmd" != *"--approve"* ]]; then
    pass "no direct merge flags and no approval"
  else
    fail "step contains direct-merge/approve flags: $run_cmd"
  fi
fi

if ((failures > 0)); then
  echo "FAIL  $failures assertion(s) failed" >&2
  exit 1
fi
echo "OK  dependabot auto-merge workflow regressions hold"
