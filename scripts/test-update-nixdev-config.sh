#!/usr/bin/env bash
#
# test-update-nixdev-config.sh — offline regression tests for the narrow
# trusted-dependency automation (scripts/update-nixdev-config.sh).
#
# Covers the acceptance-critical guard/failure behaviors:
#   A. dirty-tree refusal          (guard_canonical_clean)
#   B. lock-scope refusal          (lock_scope_check: valid bump passes;
#      root-lane movement, root-map change, version change, no-op, wrong
#      target, and subtree-node removal all handled)
#   C. validation failure          (branch kept inspectable, nothing pushed)
#   D. PR identity mismatch        (head.sha != validated commit -> no merge)
#   E. merge failure               (no fast-forward, no false success)
#   F. no-activation behavior      (static guard + happy-path behavioral
#      evidence that only the fake check.sh/nix ran)
#   G. already-up-to-date          (exit 0, no branch, no PR)
#   H. happy path end-to-end       (lock bump -> validate -> push -> PR ->
#      squash merge -> canonical fast-forwarded clean at the merged commit)
#   J. path resolution             (\$HOME defaults, explicit overrides,
#      absent-resolves-to-nothing, no hardcoded home paths)
#   K. portable paths end-to-end   (default canonical+sibling under \$HOME;
#      explicit overrides; gh-axi API fallback; missing explicit sibling
#      refused before any mutation)
#   L. PR-number parsing            (gh-axi empty/no-match envelope creates a
#      PR; genuine numeric reuse is preserved; nonnumeric output is refused)
#
# ALL OFFLINE: no network, no real nix, no real gh-axi, no GitHub
# mutations. GitHub interactions are stubbed via a fake gh-axi in a temp
# bin dir; the lock update via a fake nix; validation via a fake check.sh
# inside the fixture canonical checkout (real git + jq on tiny temp
# repositories; the fixture origin is a local bare repo behind a url.*
# insteadOf alias). Follows the repo's test conventions (PASS/FAIL/SKIP
# lines, exit 1 on failure, wired into scripts/check.sh).
#
# Usage: scripts/test-update-nixdev-config.sh
# Exit:  0 = all regressions hold (or prerequisites missing); 1 = failed.

set -u

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
UPDATER="$SCRIPT_DIR/update-nixdev-config.sh"

for tool in bash git jq mktemp; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "SKIP  $tool not found; update-nixdev-config regression tests skipped"
    exit 0
  }
done
[[ -x "$UPDATER" ]] || {
  echo "SKIP  $UPDATER not executable; tests skipped"
  exit 0
}

failures=0

fail() {
  failures=$((failures + 1))
  echo "FAIL  $*" >&2
}

dump_out() {
  echo "      (captured updater output tail):" >&2
  tail -8 <<<"$out" | sed 's/^/      /' >&2
}

pass() {
  echo "PASS  $*"
}

TD="$(mktemp -d)"
TD="$(cd "$TD" && pwd -P)"
trap 'rm -rf "$TD"' EXIT
BIN="$TD/bin"
mkdir -p "$BIN"

# ---------------------------------------------------------------------------
# lock fixtures (compact but structurally faithful: root input maps, string
# and array-path input values, and a nixdev-config subtree with its own
# inputs, so node reachability is exercised exactly like the real lock)
# ---------------------------------------------------------------------------

# gen_lock OUTFILE REV_ND REV_NPKG_ROOT REV_NPKG_INNER REV_UN_ROOT \
#   REV_UN_INNER REV_HM_ROOT REV_HM_INNER REV_TREEHOUSE VERSION EXTRA_ROOT
# A node whose rev is "-" is omitted (exercises node add/remove).
gen_lock() {
  local out="$1" nd="$2" npkg_root="$3" npkg_inner="$4" un_root="$5"
  local un_inner="$6" hm_root="$7" hm_inner="$8" treehouse="$9"
  local version="${10:-7}" extra_root="${11:-}"
  local nd_node="" hm_node="" hm_inner_node="" npkg_inner_node="" un_inner_node=""
  [[ "$nd" != "-" ]] && nd_node="\"nixdev-config\": { \"inputs\": { \"home-manager\": \"home-manager-inner\", \"nixpkgs\": \"nixpkgs-inner\", \"nixpkgs-unstable\": \"nixpkgs-unstable-inner\" }, \"locked\": { \"rev\": \"$nd\", \"narHash\": \"sha256-nd\", \"lastModified\": 1 } },"
  [[ "$hm_root" != "-" ]] && hm_node="\"home-manager-root\": { \"inputs\": { \"nixpkgs\": [\"nixpkgs-root\"] }, \"locked\": { \"rev\": \"$hm_root\", \"narHash\": \"sha256-hm\", \"lastModified\": 1 } },"
  [[ "$hm_inner" != "-" ]] && hm_inner_node="\"home-manager-inner\": { \"inputs\": { \"nixpkgs\": [\"nixdev-config\", \"nixpkgs\"] }, \"locked\": { \"rev\": \"$hm_inner\", \"narHash\": \"sha256-hmi\", \"lastModified\": 1 } },"
  [[ "$npkg_inner" != "-" ]] && npkg_inner_node="\"nixpkgs-inner\": { \"locked\": { \"rev\": \"$npkg_inner\", \"narHash\": \"sha256-ni\", \"lastModified\": 1 } },"
  [[ "$un_inner" != "-" ]] && un_inner_node="\"nixpkgs-unstable-inner\": { \"locked\": { \"rev\": \"$un_inner\", \"narHash\": \"sha256-ui\", \"lastModified\": 1 } },"
  cat > "$out" <<EOF
{
  "nodes": {
    "root": {
      "inputs": {
        "home-manager": "home-manager-root",
        "nixdev-config": "nixdev-config",
        "nixpkgs": "nixpkgs-root",
        "nixpkgs-unstable": "nixpkgs-unstable-root",
        "treehouse": "treehouse-root"$extra_root
      }
    },
    $nd_node
    $hm_node
    $hm_inner_node
    $npkg_inner_node
    "nixpkgs-root": { "locked": { "rev": "$npkg_root", "narHash": "sha256-nr", "lastModified": 1 } },
    $un_inner_node
    "nixpkgs-unstable-root": { "locked": { "rev": "$un_root", "narHash": "sha256-ur", "lastModified": 1 } },
    "treehouse-root": { "inputs": { "nixpkgs": ["nixpkgs-root"] }, "locked": { "rev": "$treehouse", "narHash": "sha256-tr", "lastModified": 1 } }
  },
  "root": "root",
  "version": $version
}
EOF
}

REV_ND_OLD="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
REV_ND_NEW="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
REV_ND_WRONG="cccccccccccccccccccccccccccccccccccccccc"
REV_NPKG="dddddddddddddddddddddddddddddddddddddddd"
REV_NPKG_ROOT_MOVED="eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
REV_UN="ffffffffffffffffffffffffffffffffffffffff"
REV_UN_INNER_OLD="1111111111111111111111111111111111111111"
REV_UN_INNER_NEW="2222222222222222222222222222222222222222"

LOCK_DIR="$TD"
gen_lock "$LOCK_DIR/old.json" "$REV_ND_OLD" "$REV_NPKG" "$REV_NPKG" "$REV_UN" \
  "$REV_UN_INNER_OLD" "$REV_NPKG" "$REV_UN_INNER_OLD" "$REV_NPKG"
gen_lock "$LOCK_DIR/new.json" "$REV_ND_NEW" "$REV_NPKG" "$REV_NPKG" "$REV_UN" \
  "$REV_UN_INNER_NEW" "$REV_NPKG" "$REV_UN_INNER_NEW" "$REV_NPKG"
gen_lock "$LOCK_DIR/violation.json" "$REV_ND_NEW" "$REV_NPKG_ROOT_MOVED" "$REV_NPKG" "$REV_UN" \
  "$REV_UN_INNER_NEW" "$REV_NPKG" "$REV_UN_INNER_NEW" "$REV_NPKG"
gen_lock "$LOCK_DIR/rootmap.json" "$REV_ND_NEW" "$REV_NPKG" "$REV_NPKG" "$REV_UN" \
  "$REV_UN_INNER_NEW" "$REV_NPKG" "$REV_UN_INNER_NEW" "$REV_NPKG" 7 ',
        "extra": "extra"'
gen_lock "$LOCK_DIR/version.json" "$REV_ND_NEW" "$REV_NPKG" "$REV_NPKG" "$REV_UN" \
  "$REV_UN_INNER_NEW" "$REV_NPKG" "$REV_UN_INNER_NEW" "$REV_NPKG" 8
gen_lock "$LOCK_DIR/removed.json" "$REV_ND_NEW" "$REV_NPKG" "$REV_NPKG" "$REV_UN" \
  "-" "$REV_NPKG" "-" "$REV_NPKG"
printf 'not json' > "$TD/bad.json"

# ---------------------------------------------------------------------------
# fixture repo + fakes
# ---------------------------------------------------------------------------

mk_fixture() {
  local canon="${1:-$TD/fixture}" bare="$TD/origin.git" fbin="$TD/fakebin"
  rm -rf "$canon" "$bare" "$fbin" "$TD/fake-state"
  mkdir -p "$canon/scripts" "$fbin"

  git init -q -b main "$canon"
  git -C "$canon" config user.email test@example.invalid
  git -C "$canon" config user.name "fixture test"
  cp "$LOCK_DIR/old.json" "$canon/flake.lock"
  echo '{ description = "fixture"; inputs = {}; }' > "$canon/flake.nix"
  cat > "$canon/scripts/check.sh" <<'EOF'
#!/usr/bin/env bash
# fake authoritative validation gate: writes a marker, then acts per
# FAKE_CHECK_RESULT (default 0).
if [[ -n "${FAKE_CHECK_MARKER:-}" ]]; then
  touch "$FAKE_CHECK_MARKER"
fi
exit "${FAKE_CHECK_RESULT:-0}"
EOF
  chmod +x "$canon/scripts/check.sh"
  git -C "$canon" add -A
  git -C "$canon" commit -q -m "fixture base"

  git init -q --bare "$bare"
  # logical github origin URL, redirected to the local bare repo (offline)
  git -C "$canon" remote add origin "https://github.com/linhnt89/nixos-config"
  git -C "$canon" config "url.file://$bare.insteadOf" "https://github.com/linhnt89/nixos-config"
  git -C "$canon" push -q origin main

  # fake nix: only handles `flake lock --update-input nixdev-config`
  cat > "$fbin/nix" <<EOF
#!/usr/bin/env bash
set -u
if [[ "\$1" != "flake" || "\$2" != "lock" ]]; then
  echo "fake nix: unexpected invocation: \$*" >&2
  exit 2
fi
cp "\${NIXDEV_UPDATE_TEST_NEW_LOCK:?}" ./flake.lock || exit 1
echo "fake nix: re-pinned flake.lock (test fixture)"
EOF
  chmod +x "$fbin/nix"

  # fake gh-axi: deterministic responses driven by FAKE_* env; logs every
  # call with its arguments for assertions. Simulates a real squash merge
  # by committing the branch tree onto the base inside the bare origin.
  cat > "$fbin/gh-axi" <<EOF
#!/usr/bin/env bash
set -u
{
  echo "call: \$*"
} >> "\$FAKE_LOG"

branch="deps/nixdev-config-bump-\${FAKE_TARGET_REV:0:8}"
state_dir="$TD/fake-state"
mkdir -p "\$state_dir"

# outage simulation: FAKE_API_DOWN=1 fails every api call (sustained
# GitHub outage); FAKE_API_FLAP=1 fails the first api call (transient).
if [[ "\${FAKE_API_DOWN:-0}" == "1" ]]; then
  echo "gh: No server is currently available to service your request. (HTTP 503)" >&2
  exit 1
fi
if [[ "\${FAKE_API_FLAP:-0}" == "1" ]]; then
  if [[ ! -f "\$state_dir/flapped" ]]; then
    touch "\$state_dir/flapped"
    echo "gh: No server is currently available to service your request. (HTTP 503)" >&2
    exit 1
  fi
fi

case "\$1" in
  api)
    path="\$2"
    expr=""
    prev=""
    for a in "\$@"; do
      if [[ "\$prev" == "--jq" ]]; then expr="\$a"; fi
      prev="\$a"
    done
    if [[ "\$path" == "/repos/linhnt89/nixos-config" ]] && [[ "\$expr" == ".full_name" ]]; then
      val="linhnt89/nixos-config"
    elif [[ "\$path" == /repos/linhnt89/nixdev-config/commits/HEAD ]] && [[ "\$expr" == ".sha" ]]; then
      val="\${FAKE_ND_HEAD:-$REV_ND_NEW}"
    elif [[ "\$path" == /repos/linhnt89/nixos-config/pulls?state=open* ]]; then
      # gh-axi --jq empty returns this TOON envelope; a numeric jq result
      # is rendered as a raw scalar. Keep both shapes in the fixture.
      if [[ -n "\${FAKE_PR_QUERY_OUTPUT:-}" ]]; then
        printf '%s\n' "\$FAKE_PR_QUERY_OUTPUT"
        exit 0
      elif [[ -f "\$state_dir/created" ]]; then
        printf '1\n'
        exit 0
      else
        printf 'api_response:\n  body: ""\n  truncated: false\n'
        exit 0
      fi
    elif [[ "\$path" == /repos/linhnt89/nixos-config/pulls/1 ]]; then
      case "\$expr" in
        '.state') val="\${FAKE_PR_STATE:-open}" ;;
        '.base.ref') val="\${FAKE_PR_BASE_REF:-main}" ;;
        '.head.ref') val="\${FAKE_PR_HEAD_REF:-\$branch}" ;;
        '.head.sha') val="\${FAKE_PR_HEAD_SHA:-\$(git -C "$canon" rev-parse "refs/heads/\$branch" 2>/dev/null || echo '')}" ;;
        '.mergeable') val="\${FAKE_PR_MERGEABLE:-true}" ;;
        '.merged')
          if [[ -n "\${FAKE_PR_MERGED:-}" ]]; then
            val="\$FAKE_PR_MERGED"
          elif [[ -f "\$state_dir/merged" ]]; then
            val="true"
          else
            val="false"
          fi
          ;;
        '.merge_commit_sha') val="\$(cat "\$state_dir/merged" 2>/dev/null | sed -n 's/^MERGED=//p' || true)" ;;
        *) val="" ;;
      esac
    else
      val=""
    fi
    printf 'api_response:\n  body: %s\n  truncated: false\n' "\$val"
    ;;
  pr)
    if [[ "\${2:-}" == "create" ]]; then
      touch "\$state_dir/created"
      echo "https://github.com/linhnt89/nixos-config/pull/1"
    elif [[ "\${2:-}" == "merge" ]]; then
      if [[ "\${FAKE_MERGE_FAIL:-0}" == "1" ]]; then
        echo "error: fake merge failure" >&2
        exit 1
      fi
      base_sha="\$(git --git-dir="$bare" rev-parse refs/heads/main)"
      head_sha="\$(git -C "$canon" rev-parse "refs/heads/\$branch")"
      tree="\$(git -C "$canon" rev-parse "\$head_sha^{tree}")"
      merged="\$(git --git-dir="$bare" commit-tree "\$tree" -p "\$base_sha" -m "chore(deps): bump nixdev-config input")"
      git --git-dir="$bare" update-ref refs/heads/main "\$merged" "\$base_sha"
      git --git-dir="$bare" update-ref -d "refs/heads/\$branch" 2>/dev/null || true
      echo "MERGED=\$merged" > "\$state_dir/merged"
      echo "merged \$merged"
    else
      echo "error: fake gh-axi: unknown pr subcommand: \${2:-}" >&2
      exit 1
    fi
    ;;
  *)
    echo "error: fake gh-axi: unexpected top-level: \$1" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$fbin/gh-axi"
}

# mk_nd_fixture SRC_CHECKOUT BARE_ORIGIN -> a real local worktree that
# stands in for the public linhnt89/nixdev-config sibling source checkout:
# a `main` branch pushed to a local bare `origin` behind a url.* insteadOf
# alias (offline; `git ls-remote --symref origin HEAD` in the updater
# resolves the upstream head against this mirror).
mk_nd_fixture() {
  local nd="$1" nd_bare="$2"
  rm -rf "$nd" "$nd_bare"
  mkdir -p "$nd"
  git init -q -b main "$nd"
  git -C "$nd" config user.email test@example.invalid
  git -C "$nd" config user.name "fixture test"
  cat > "$nd/flake.nix" <<'NEOF'
{
  description = "nixdev-config fixture source";
  inputs = {};
  outputs = { self }: { };
}
NEOF
  git -C "$nd" add -A
  git -C "$nd" commit -q -m "fixture nixdev-config source"
  git init -q --bare -b main "$nd_bare"
  git -C "$nd" remote add origin "https://github.com/linhnt89/nixdev-config"
  git -C "$nd" config "url.file://$nd_bare.insteadOf" "https://github.com/linhnt89/nixdev-config"
  git -C "$nd" push -q origin main
}

# run_updater -> runs the real updater against the fixture with the fixed
# test env. Scenario overrides are exported by the caller first.
#   - NIXDEV_UPDATE_TARGET_REV exported-empty forces the sibling/gh-axi
#     upstream-head resolution path; exported non-empty pins the rev;
#     unexported falls back to REV_ND_NEW (existing scenarios).
#   - NIXDEV_UPDATE_CANONICAL_REPO exported wins; HOME_DIR=<dir>
#     exercises the $HOME default under $TD/<dir>; otherwise the canonical
#     fixture at $TD/fixture is used explicitly.
#   - NIXDEV_UPDATE_NIXDEV_SRC exported is forwarded (sibling override).
run_updater() {
  local envs=(
    NIXDEV_UPDATE_GH_AXI_BIN="$TD/fakebin/gh-axi"
    NIXDEV_UPDATE_NIX_BIN="$TD/fakebin/nix"
    NIXDEV_UPDATE_RETRIES="${NIXDEV_UPDATE_RETRIES:-1}"
    NIXDEV_UPDATE_RETRY_DELAY=0
    NIXDEV_UPDATE_POLL_TRIES=3
    NIXDEV_UPDATE_POLL_DELAY=0
    NIXDEV_UPDATE_TEST_NEW_LOCK="${NIXDEV_UPDATE_TEST_NEW_LOCK:-$LOCK_DIR/new.json}"
    FAKE_LOG="$FAKE_LOG"
    FAKE_TARGET_REV="${FAKE_TARGET_REV:-$REV_ND_NEW}"
  )
  local t="${NIXDEV_UPDATE_TARGET_REV+x}"
  if [[ "$t" == "x" && -z "${NIXDEV_UPDATE_TARGET_REV}" ]]; then
    : # explicit empty: exercise the sibling/gh-axi upstream-head resolution
  elif [[ -n "${NIXDEV_UPDATE_TARGET_REV:-}" ]]; then
    envs+=(NIXDEV_UPDATE_TARGET_REV="$NIXDEV_UPDATE_TARGET_REV")
  else
    envs+=(NIXDEV_UPDATE_TARGET_REV="$REV_ND_NEW")
  fi
  if [[ -n "${NIXDEV_UPDATE_CANONICAL_REPO:-}" ]]; then
    envs+=(NIXDEV_UPDATE_CANONICAL_REPO="$NIXDEV_UPDATE_CANONICAL_REPO")
  elif [[ -n "${HOME_DIR:-}" ]]; then
    envs+=(HOME="$TD/$HOME_DIR")
  else
    envs+=(NIXDEV_UPDATE_CANONICAL_REPO="$TD/fixture")
  fi
  [[ -z "${NIXDEV_UPDATE_NIXDEV_SRC:-}" ]] || envs+=(NIXDEV_UPDATE_NIXDEV_SRC="$NIXDEV_UPDATE_NIXDEV_SRC")
  local v
  for v in FAKE_MERGE_FAIL FAKE_PR_HEAD_SHA FAKE_PR_MERGEABLE FAKE_PR_STATE \
           FAKE_PR_MERGED FAKE_PR_HEAD_REF FAKE_PR_BASE_REF FAKE_PR_QUERY_OUTPUT \
           FAKE_CHECK_MARKER FAKE_CHECK_RESULT FAKE_API_DOWN FAKE_API_FLAP \
           FAKE_ND_HEAD; do
    if [[ -n "${!v:-}" ]]; then
      envs+=("$v=${!v}")
    fi
  done
  (cd "$TD" && env "${envs[@]}" "$UPDATER" --yes)
}

# ---------------------------------------------------------------------------
# A. dirty-tree refusal
# ---------------------------------------------------------------------------

echo '== A. dirty-tree refusal (guard_canonical_clean) =='

mk_fixture
if NIXDEV_UPDATE_CANONICAL_REPO="$TD/fixture" "$UPDATER" --test-guard clean >/dev/null 2>&1; then
  pass "clean canonical checkout accepted by the guard"
else
  fail "clean canonical checkout rejected by the guard"
fi

for variant in untracked staged unstaged; do
  case "$variant" in
    untracked) echo junk > "$TD/fixture/junk.txt" ;;
    staged) echo change > "$TD/fixture/flake.nix" && git -C "$TD/fixture" add flake.nix ;;
    unstaged) echo change >> "$TD/fixture/flake.nix" ;;
  esac
  out="$(NIXDEV_UPDATE_CANONICAL_REPO="$TD/fixture" "$UPDATER" --test-guard clean 2>&1)" && rc=0 || rc=$?
  case "$variant" in
    untracked) rm -f "$TD/fixture/junk.txt" ;;
    staged|unstaged) git -C "$TD/fixture" checkout -q -- flake.nix ;;
  esac
  if [[ $rc -ne 0 ]]; then
    pass "dirty tree refused ($variant)"
  else
    fail "dirty tree NOT refused ($variant)"
  fi
done

bronly=0
git -C "$TD/fixture" checkout -q -b other
out="$(NIXDEV_UPDATE_CANONICAL_REPO="$TD/fixture" "$UPDATER" --test-guard clean 2>&1)" && rc=0 || rc=$?
git -C "$TD/fixture" checkout -q main 2>/dev/null || bronly=1
if [[ $rc -ne 0 ]]; then
  pass "wrong-branch checkout refused"
else
  fail "wrong-branch checkout NOT refused"
fi

out="$(NIXDEV_UPDATE_CANONICAL_REPO="$TD/nonexistent" "$UPDATER" --test-guard clean 2>&1)" && rc=0 || rc=$?
[[ $rc -ne 0 ]] && pass "missing canonical path refused" || fail "missing canonical path NOT refused"

# ---------------------------------------------------------------------------
# B. lock-scope analysis
# ---------------------------------------------------------------------------

echo '== B. lock-scope analysis (lock_scope_check) =='

$UPDATER --test-guard lock-scope "$LOCK_DIR/old.json" "$LOCK_DIR/new.json" "$REV_ND_NEW" >/dev/null 2>&1 \
  && pass "valid lock-only bump accepted (subtree changes only)" \
  || fail "valid lock-only bump rejected"

$UPDATER --test-guard lock-scope "$LOCK_DIR/old.json" "$LOCK_DIR/violation.json" "$REV_ND_NEW" >/dev/null 2>&1 \
  && fail "scope violation (root nixpkgs lane moved) NOT refused" \
  || pass "scope violation (root nixpkgs lane moved) refused"

$UPDATER --test-guard lock-scope "$LOCK_DIR/old.json" "$LOCK_DIR/rootmap.json" "$REV_ND_NEW" >/dev/null 2>&1 \
  && fail "root input map change NOT refused" \
  || pass "root input map change refused"

$UPDATER --test-guard lock-scope "$LOCK_DIR/old.json" "$LOCK_DIR/version.json" "$REV_ND_NEW" >/dev/null 2>&1 \
  && fail "lock version change NOT refused" \
  || pass "lock version change refused"

$UPDATER --test-guard lock-scope "$LOCK_DIR/old.json" "$LOCK_DIR/old.json" "$REV_ND_NEW" >/dev/null 2>&1 \
  && fail "no-op lock update NOT refused" \
  || pass "no-op lock update refused (already up to date)"

$UPDATER --test-guard lock-scope "$LOCK_DIR/old.json" "$LOCK_DIR/new.json" "$REV_ND_WRONG" >/dev/null 2>&1 \
  && fail "rev != upstream target NOT refused" \
  || pass "rev != upstream target refused"

$UPDATER --test-guard lock-scope "$LOCK_DIR/old.json" "$LOCK_DIR/removed.json" "$REV_ND_NEW" >/dev/null 2>&1 \
  && pass "subtree-node removal inside the nixdev-config scope accepted" \
  || fail "subtree-node removal inside the nixdev-config scope rejected"

$UPDATER --test-guard lock-scope "$TD/bad.json" "$LOCK_DIR/new.json" "$REV_ND_NEW" >/dev/null 2>&1 \
  && fail "invalid old lock NOT refused" \
  || pass "invalid old lock refused"

# ---------------------------------------------------------------------------
# F (static). no-activation guard
# ---------------------------------------------------------------------------

echo '== F. no-activation (static guard) =='

$UPDATER --test-guard no-activation >/dev/null 2>&1 \
  && pass "no activation/destructive commands in the executable script body" \
  || fail "no-activation static guard failed"

# ---------------------------------------------------------------------------
# C. validation failure (flow; branch inspectable, nothing pushed)
# ---------------------------------------------------------------------------

echo '== C. validation failure leaves the branch inspectable, nothing pushed =='

mk_fixture
export FAKE_LOG="$TD/logC"
FAKE_CHECK_MARKER="$TD/check-ran" FAKE_CHECK_RESULT=1 out="$(run_updater 2>&1)" && rc=0 || rc=$?
unset FAKE_CHECK_MARKER FAKE_CHECK_RESULT
cur="$(git -C "$TD/fixture" rev-parse --abbrev-ref HEAD)"
commits="$(git -C "$TD/fixture" rev-list --count main..HEAD 2>/dev/null || echo 0)"
pushed="$(git --git-dir="$TD/origin.git" for-each-ref refs/heads --format='%(refname:short)' | grep -c 'deps/' || true)"
if [[ $rc -ne 0 && "$cur" == deps/* && "$commits" == "1" && "$pushed" == "0" ]]; then
  pass "validation failure aborts before push; branch kept inspectable (rc=$rc)"
else
  fail "validation failure handling wrong (rc=$rc branch=$cur commits=$commits pushed=$pushed)"
  dump_out
fi

# ---------------------------------------------------------------------------
# D. PR identity mismatch -> no merge
# ---------------------------------------------------------------------------

echo '== D. PR identity mismatch refused before merge =='

mk_fixture
export FAKE_LOG="$TD/logD" FAKE_PR_HEAD_SHA="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
out="$(run_updater 2>&1)" && rc=0 || rc=$?
origin_main="$(git --git-dir="$TD/origin.git" rev-parse refs/heads/main)"
base_sha="$(git --git-dir="$TD/origin.git" rev-parse refs/heads/main)"
cur="$(git -C "$TD/fixture" rev-parse --abbrev-ref HEAD)"
log_has_merge="$(grep -c 'call: pr merge' "$TD/logD" || true)"
if [[ $rc -ne 0 && "$cur" == deps/* && "$log_has_merge" == "0" && "$origin_main" == "$base_sha" ]]; then
  pass "PR identity mismatch refuses the merge (rc=$rc)"
else
  fail "PR identity mismatch NOT handled (rc=$rc branch=$cur merge-calls=$log_has_merge)"
  dump_out
fi
unset FAKE_PR_HEAD_SHA

# ---------------------------------------------------------------------------
# E. merge failure -> no fast-forward, no false success
# ---------------------------------------------------------------------------

echo '== E. merge failure leaves the PR open, no fast-forward =='

mk_fixture
export FAKE_LOG="$TD/logE" FAKE_MERGE_FAIL=1 FAKE_PR_MERGED=false
out="$(run_updater 2>&1)" && rc=0 || rc=$?
origin_main="$(git --git-dir="$TD/origin.git" rev-parse refs/heads/main)"
base_sha="$(git --git-dir="$TD/origin.git" rev-parse refs/heads/main)"
cur="$(git -C "$TD/fixture" rev-parse --abbrev-ref HEAD)"
if [[ $rc -ne 0 && "$cur" == deps/* && "$origin_main" == "$base_sha" ]]; then
  pass "merge failure aborts without fast-forward (rc=$rc)"
else
  fail "merge failure NOT handled (rc=$rc branch=$cur origin-moved=$([[ "$origin_main" != "$base_sha" ]] && echo yes || echo no))"
  dump_out
fi
unset FAKE_MERGE_FAIL FAKE_PR_MERGED

# ---------------------------------------------------------------------------
# L. PR-number parsing: no-match envelope, numeric reuse, invalid output
# ---------------------------------------------------------------------------

echo '== L. PR-number parsing and PR discovery =='

# The reported gh-axi no-match shape is `api_response: body: ""`.
# It must take the create path, never become /pull/"".
mk_fixture
export FAKE_LOG="$TD/logL1"
out="$(run_updater 2>&1)" && rc=0 || rc=$?
create_calls="$(grep -c 'call: pr create' "$TD/logL1" || true)"
malformed_api="$(grep -cF '/pulls/""' "$TD/logL1" || true)"
malformed_merge="$(grep -cF 'call: pr merge ""' "$TD/logL1" || true)"
if [[ $rc -eq 0 && "$create_calls" == "1" && "$malformed_api" == "0" && "$malformed_merge" == "0" ]]; then
  pass "empty gh-axi envelope creates a PR without an empty PR URL/API path"
else
  fail "empty gh-axi envelope was treated as an existing PR (rc=$rc create=$create_calls malformed-api=$malformed_api malformed-merge=$malformed_merge)"
  dump_out
fi

# A real open PR is still reused when gh-axi returns its numeric jq scalar.
mk_fixture
mkdir -p "$TD/fake-state"
touch "$TD/fake-state/created"
export FAKE_LOG="$TD/logL2"
out="$(run_updater 2>&1)" && rc=0 || rc=$?
create_calls="$(grep -c 'call: pr create' "$TD/logL2" || true)"
merge_calls="$(grep -c 'call: pr merge 1' "$TD/logL2" || true)"
if [[ $rc -eq 0 && "$create_calls" == "0" && "$merge_calls" == "1" ]] \
   && grep -q 'reusing existing open PR #1' <<<"$out"; then
  pass "genuine existing open PR #1 is reused and merged"
else
  fail "genuine existing open PR was not reused (rc=$rc create=$create_calls merge=$merge_calls)"
  dump_out
fi

# Nonnumeric output is neither an existing PR nor an identifier for the
# post-create lookup; it must stop before any malformed identity/API/merge use.
mk_fixture
export FAKE_LOG="$TD/logL3" FAKE_PR_QUERY_OUTPUT='not-a-number'
out="$(run_updater 2>&1)" && rc=0 || rc=$?
unset FAKE_PR_QUERY_OUTPUT
create_calls="$(grep -c 'call: pr create' "$TD/logL3" || true)"
malformed_api="$(grep -cF '/pulls/not-a-number' "$TD/logL3" || true)"
malformed_merge="$(grep -cF 'call: pr merge not-a-number' "$TD/logL3" || true)"
malformed_url="$(grep -cF 'pull/not-a-number' <<<"$out" || true)"
if [[ $rc -ne 0 && "$create_calls" == "1" && "$malformed_api" == "0" \
      && "$malformed_merge" == "0" && "$malformed_url" == "0" ]]; then
  pass "nonnumeric PR output is refused before URL/API/merge use"
else
  fail "nonnumeric PR output escaped validation (rc=$rc create=$create_calls malformed-api=$malformed_api malformed-merge=$malformed_merge malformed-url=$malformed_url)"
  dump_out
fi

# ---------------------------------------------------------------------------
# I. GitHub outage handling
# ---------------------------------------------------------------------------

echo '== I. GitHub outage handling (retry recovers; sustained outage stops) =='

# transient outage: the first api call fails with 503, retries recover
mk_fixture
BASE_SHA="$(git -C "$TD/fixture" rev-parse main)"
export FAKE_LOG="$TD/logI1" FAKE_API_FLAP=1 FAKE_API_DOWN=0 NIXDEV_UPDATE_RETRIES=2
out="$(run_updater 2>&1)" && rc=0 || rc=$?
unset FAKE_API_FLAP NIXDEV_UPDATE_RETRIES
new_sha="$(git -C "$TD/fixture" rev-parse HEAD)"
if [[ $rc -eq 0 && "$new_sha" != "$BASE_SHA" && "$(git -C "$TD/fixture" rev-parse --abbrev-ref HEAD)" == "main" ]]; then
  pass "transient 503 recovered by retry; flow completed (rc=0)"
else
  fail "transient 503 NOT recovered (rc=$rc)"
  dump_out
fi

# sustained outage: fails hard before any branch/PR/merge mutation
mk_fixture
export FAKE_LOG="$TD/logI2" FAKE_API_DOWN=1
out="$(run_updater 2>&1)" && rc=0 || rc=$?
unset FAKE_API_DOWN
cur="$(git -C "$TD/fixture" rev-parse --abbrev-ref HEAD)"
log_has_merge="$(grep -c 'call: pr merge' "$TD/logI2" || true)"
if [[ $rc -ne 0 && "$cur" == "main" && "$log_has_merge" == "0" ]]; then
  pass "sustained outage stops before any mutation (no branch, no PR, no merge)"
else
  fail "sustained outage NOT handled (rc=$rc branch=$cur merge-calls=$log_has_merge)"
  dump_out
fi
unset FAKE_API_DOWN

# ---------------------------------------------------------------------------
# G. already up to date
# ---------------------------------------------------------------------------

echo '== G. already up to date -> exit 0, no branch, no PR =='

mk_fixture
export FAKE_LOG="$TD/logG"
NIXDEV_UPDATE_TARGET_REV="$REV_ND_OLD" out="$(run_updater 2>&1)" && rc=0 || rc=$?
unset NIXDEV_UPDATE_TARGET_REV
branches_after="$(git -C "$TD/fixture" for-each-ref --format='%(refname:short)' | grep -c 'deps/' || true)"
if [[ $rc -eq 0 && "$branches_after" == "0" ]]; then
  pass "already-up-to-date exits 0 without a branch or PR"
else
  fail "already-up-to-date handling wrong (rc=$rc branches=$branches_after)"
  dump_out
fi

# ---------------------------------------------------------------------------
# H. happy path end-to-end (+ F behavioral: only the fake check ran)
# ---------------------------------------------------------------------------

echo '== H. happy path: bump -> validate -> push -> PR -> squash merge -> fast-forward =='

mk_fixture
rm -f "$TD/check-ran" "$TD/activation-ran"
BASE_SHA="$(git -C "$TD/fixture" rev-parse main)"
export FAKE_LOG="$TD/logH"
FAKE_CHECK_MARKER="$TD/check-ran" FAKE_CHECK_RESULT=0 out="$(run_updater 2>&1)" && rc=0 || rc=$?
unset FAKE_CHECK_MARKER FAKE_CHECK_RESULT

new_sha="$(git -C "$TD/fixture" rev-parse HEAD)"
origin_main="$(git --git-dir="$TD/origin.git" rev-parse refs/heads/main)"
cur="$(git -C "$TD/fixture" rev-parse --abbrev-ref HEAD)"
dirty="$(git -C "$TD/fixture" status --porcelain)"
branch_left="$(git -C "$TD/fixture" branch | grep -c 'deps/' || true)"
ok=1
[[ $rc -eq 0 ]] || { fail "happy path exit code: $rc"; ok=0; }
[[ "$cur" == "main" ]] || { fail "canonical not back on main"; ok=0; }
[[ "$new_sha" == "$origin_main" && "$new_sha" != "$BASE_SHA" ]] || { fail "canonical main not fast-forwarded to the merged commit"; ok=0; }
[[ -z "$dirty" ]] || { fail "canonical checkout dirty after fast-forward: $dirty"; ok=0; }
[[ "$branch_left" == "0" ]] || { fail "temp branch not deleted"; ok=0; }
[[ -f "$TD/check-ran" ]] || { fail "fake check.sh was not run"; ok=0; }
[[ -f "$TD/fake-state/created" ]] || { fail "PR was not created (fake gh-axi state)"; ok=0; }
grep -q 'call: pr merge' "$TD/logH" || { fail "PR was not merged (fake gh-axi log)"; ok=0; }
[[ $ok -eq 1 ]] && pass "happy path end-to-end: validated, PR #1 squash-merged, canonical fast-forwarded clean at $new_sha"
if [[ $ok -eq 0 ]]; then
  dump_out
fi

# ---------------------------------------------------------------------------
# J. path resolution: defaults, overrides, and no hardcoded home paths
# ---------------------------------------------------------------------------

echo '== J. path defaults, overrides, and no hardcoded home paths =='

PT="$TD/pathtests"
mkdir -p "$PT/homedef/firstmate/projects/nixos-config"
mkdir -p "$PT/homedef/firstmate/projects/nixdev-config"
mkdir -p "$PT/homeless" "$PT/override-a"

# default canonical + sibling resolve under \$HOME (in a non-repo cwd so
# the git-worktree discovery fallback cannot fire)
out="$(cd "$TD" && HOME="$PT/homedef" "$UPDATER" --test-guard paths 2>&1)" && rc=0 || rc=$?
if [[ $rc -eq 0 ]] \
   && grep -qx "canonical=$PT/homedef/firstmate/projects/nixos-config" <<<"$out" \
   && grep -qx "sibling=$PT/homedef/firstmate/projects/nixdev-config" <<<"$out"; then
  pass "default paths resolve under \$HOME (firstmate/projects layout)"
else
  fail "default paths did NOT resolve under \$HOME"
  dump_out
fi

# explicit overrides beat \$HOME defaults
out="$(cd "$TD" && HOME="$PT/homedef" \
  NIXDEV_UPDATE_CANONICAL_REPO="$PT/override-a" \
  NIXDEV_UPDATE_NIXDEV_SRC="$PT/override-a" \
  "$UPDATER" --test-guard paths 2>&1)" && rc=0 || rc=$?
if [[ $rc -eq 0 ]] && grep -qx "canonical=$PT/override-a" <<<"$out" \
   && grep -qx "sibling=$PT/override-a" <<<"$out"; then
  pass "explicit overrides beat \$HOME defaults"
else
  fail "explicit overrides did NOT beat \$HOME defaults"
  dump_out
fi

# no defaults and no overrides: nothing resolves (no hidden fallback repo)
out="$(cd "$TD" && HOME="$PT/homeless" "$UPDATER" --test-guard paths 2>&1)" && rc=0 || rc=$?
if grep -qx 'canonical_rc=1' <<<"$out" && grep -qx 'sibling_rc=1' <<<"$out" \
   && grep -qx 'canonical=' <<<"$out" && grep -qx 'sibling=' <<<"$out"; then
  pass "absent defaults/overrides resolve to nothing"
else
  fail "absent defaults/overrides did NOT resolve to nothing"
  dump_out
fi

# no hardcoded home paths in tracked code/docs, and both overrides are
# documented; every firstmate/projects reference is \$HOME-derived
hd=0
for f in scripts/update-nixdev-config.sh docs/updates-runbook.md \
         docs/nixdev-config-integration.md README.md AGENTS.md; do
  if grep -n '/ho[m]e/' "$f" >/dev/null 2>&1; then
    echo "FAIL  hardcoded absolute home path in $f:" >&2
    grep -n '/ho[m]e/' "$f" | sed 's/^/      /' >&2
    hd=1
  fi
  if grep -n 'firstmate/projects' "$f" | grep -vE '\$HOME|\$\{HOME' >/dev/null 2>&1; then
    echo "FAIL  non-\$HOME firstmate/projects path in $f:" >&2
    grep -n 'firstmate/projects' "$f" | grep -vE '\$HOME|\$\{HOME' | sed 's/^/      /' >&2
    hd=1
  fi
done
grep -nE '/ho[m]e/' scripts/test-update-nixdev-config.sh \
  | grep -vE '\$TD/home|\$PT/homedef' >/dev/null 2>&1 \
  && { echo "FAIL  hardcoded absolute home path in test script" >&2; hd=1; }
grep -q 'NIXDEV_UPDATE_NIXDEV_SRC' scripts/update-nixdev-config.sh || { echo "FAIL  script does not document NIXDEV_UPDATE_NIXDEV_SRC" >&2; hd=1; }
grep -q 'NIXDEV_UPDATE_CANONICAL_REPO' docs/updates-runbook.md || { echo "FAIL  runbook does not document NIXDEV_UPDATE_CANONICAL_REPO" >&2; hd=1; }
grep -q 'NIXDEV_UPDATE_NIXDEV_SRC' docs/updates-runbook.md || { echo "FAIL  runbook does not document NIXDEV_UPDATE_NIXDEV_SRC" >&2; hd=1; }
if [[ $hd -eq 0 ]]; then
  pass "no hardcoded home paths; both overrides documented in code and runbook"
else
  fail "hardcoded home paths or missing override documentation"
fi
# ---------------------------------------------------------------------------
# K. portable default/override paths end-to-end + upstream-head resolution
# ---------------------------------------------------------------------------

echo '== K. default/override paths end-to-end; sibling/API upstream-head =='

# K1: BOTH \$HOME defaults - canonical checkout and sibling nixdev-config
# source under $TD/home/firstmate/projects/*; upstream head resolved from
# the default sibling (no gh-axi nixdev-config API call).
mkdir -p "$TD/home"
mk_fixture "$TD/home/firstmate/projects/nixos-config"
mk_nd_fixture "$TD/home/firstmate/projects/nixdev-config" "$TD/nd-origin.git"
SIB_HEAD="$(git -C "$TD/home/firstmate/projects/nixdev-config" rev-parse main)"
gen_lock "$LOCK_DIR/new-sib-k1.json" "$SIB_HEAD" "$REV_NPKG" "$REV_NPKG" "$REV_UN" \
  "$REV_UN_INNER_NEW" "$REV_NPKG" "$REV_UN_INNER_NEW" "$REV_NPKG"
export FAKE_LOG="$TD/logK1" NIXDEV_UPDATE_TARGET_REV="" \
  NIXDEV_UPDATE_TEST_NEW_LOCK="$LOCK_DIR/new-sib-k1.json" FAKE_TARGET_REV="$SIB_HEAD"
BASE_SHA="$(git -C "$TD/home/firstmate/projects/nixos-config" rev-parse main)"
out="$(HOME_DIR=home run_updater 2>&1)" && rc=0 || rc=$?
unset NIXDEV_UPDATE_TARGET_REV NIXDEV_UPDATE_TEST_NEW_LOCK FAKE_TARGET_REV
new_sha="$(git -C "$TD/home/firstmate/projects/nixos-config" rev-parse HEAD 2>/dev/null || echo '')"
cur="$(git -C "$TD/home/firstmate/projects/nixos-config" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
ndapi="$(grep -c 'nixdev-config/commits/HEAD' "$TD/logK1" || true)"
if [[ $rc -eq 0 && "$new_sha" != "$BASE_SHA" && "$cur" == "main" \
      && "$ndapi" == "0" && -f "$TD/fake-state/created" ]]; then
  pass "default paths end-to-end: \$HOME canonical + \$HOME sibling resolved the upstream head"
else
  fail "default paths end-to-end FAILED (rc=$rc branch=$cur nd-api-calls=$ndapi)"
  dump_out
fi

# K2: BOTH explicit overrides beat \$HOME defaults end-to-end (canonical at
# $TD/fixture-override, sibling at $TD/sib2; the real \$HOME default is
# present on this machine and must NOT be used).
mk_fixture "$TD/fixture-override"
mk_nd_fixture "$TD/sib2" "$TD/sib2-origin.git"
SIB2_HEAD="$(git -C "$TD/sib2" rev-parse main)"
gen_lock "$LOCK_DIR/new-sib-k2.json" "$SIB2_HEAD" "$REV_NPKG" "$REV_NPKG" "$REV_UN" \
  "$REV_UN_INNER_NEW" "$REV_NPKG" "$REV_UN_INNER_NEW" "$REV_NPKG"
export FAKE_LOG="$TD/logK2" NIXDEV_UPDATE_TARGET_REV="" \
  NIXDEV_UPDATE_CANONICAL_REPO="$TD/fixture-override" \
  NIXDEV_UPDATE_NIXDEV_SRC="$TD/sib2" \
  NIXDEV_UPDATE_TEST_NEW_LOCK="$LOCK_DIR/new-sib-k2.json" FAKE_TARGET_REV="$SIB2_HEAD"
BASE_SHA="$(git -C "$TD/fixture-override" rev-parse main)"
out="$(run_updater 2>&1)" && rc=0 || rc=$?
unset NIXDEV_UPDATE_TARGET_REV NIXDEV_UPDATE_CANONICAL_REPO \
  NIXDEV_UPDATE_NIXDEV_SRC NIXDEV_UPDATE_TEST_NEW_LOCK FAKE_TARGET_REV
new_sha="$(git -C "$TD/fixture-override" rev-parse HEAD 2>/dev/null || echo '')"
cur="$(git -C "$TD/fixture-override" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
ndapi="$(grep -c 'nixdev-config/commits/HEAD' "$TD/logK2" || true)"
if [[ $rc -eq 0 && "$new_sha" != "$BASE_SHA" && "$cur" == "main" && "$ndapi" == "0" ]]; then
  pass "explicit override end-to-end: canonical+source overrides win over \$HOME defaults"
else
  fail "explicit override end-to-end FAILED (rc=$rc branch=$cur nd-api-calls=$ndapi)"
  dump_out
fi

# K3: no sibling checkout anywhere -> gh-axi API lookup (previous behavior
# preserved); target REV_ND_NEW via the fake nixdev-config commits/HEAD.
mkdir -p "$TD/home3"
mk_fixture "$TD/home3/firstmate/projects/nixos-config"
export FAKE_LOG="$TD/logK3" NIXDEV_UPDATE_TARGET_REV="" \
  FAKE_ND_HEAD="$REV_ND_NEW"
BASE_SHA="$(git -C "$TD/home3/firstmate/projects/nixos-config" rev-parse main)"
out="$(HOME_DIR=home3 run_updater 2>&1)" && rc=0 || rc=$?
unset NIXDEV_UPDATE_TARGET_REV FAKE_ND_HEAD
new_sha="$(git -C "$TD/home3/firstmate/projects/nixos-config" rev-parse HEAD 2>/dev/null || echo '')"
cur="$(git -C "$TD/home3/firstmate/projects/nixos-config" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '')"
ndapi="$(grep -c 'nixdev-config/commits/HEAD' "$TD/logK3" || true)"
if [[ $rc -eq 0 && "$new_sha" != "$BASE_SHA" && "$cur" == "main" && "$ndapi" -ge 1 ]]; then
  pass "absent default sibling falls back to the gh-axi API (previous behavior preserved)"
else
  fail "API fallback FAILED (rc=$rc branch=$cur nd-api-calls=$ndapi)"
  dump_out
fi

# K4: missing EXPLICIT sibling override refuses before any mutation
mk_fixture
export FAKE_LOG="$TD/logK4" NIXDEV_UPDATE_TARGET_REV="" \
  NIXDEV_UPDATE_NIXDEV_SRC="$TD/no-such-sibling"
out="$(run_updater 2>&1)" && rc=0 || rc=$?
unset NIXDEV_UPDATE_TARGET_REV NIXDEV_UPDATE_NIXDEV_SRC
cur="$(git -C "$TD/fixture" rev-parse --abbrev-ref HEAD)"
created="$(test -f "$TD/fake-state/created" && echo yes || echo no)"
ndapi="$(grep -c 'nixdev-config/commits/HEAD' "$TD/logK4" || true)"
if [[ $rc -ne 0 && "$cur" == "main" && "$created" == "no" && "$ndapi" == "0" ]]; then
  pass "missing explicit NIXDEV_UPDATE_NIXDEV_SRC refused before any mutation"
else
  fail "missing explicit NIXDEV_UPDATE_NIXDEV_SRC NOT refused (rc=$rc branch=$cur pr-created=$created)"
  dump_out
fi

# ---------------------------------------------------------------------------

echo
if [ "$failures" -eq 0 ]; then
  echo 'PASS — update-nixdev-config regression tests hold.'
  exit 0
fi
echo "FAIL — $failures regression test(s) failed." >&2
exit 1