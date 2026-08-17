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
  local canon="$TD/fixture" bare="$TD/origin.git" fbin="$TD/fakebin"
  rm -rf "$canon" "$bare" "$fbin"
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
    elif [[ "\$path" == /repos/linhnt89/nixos-config/pulls?state=open* ]]; then
      if [[ -f "\$state_dir/created" ]]; then
        val="1"
      else
        val=""
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

# run_updater -> runs the real updater against the fixture with the fixed
# test env. Scenario overrides are exported by the caller first.
run_updater() {
  local envs=(
    NIXDEV_UPDATE_CANONICAL_REPO="$TD/fixture"
    NIXDEV_UPDATE_GH_AXI_BIN="$TD/fakebin/gh-axi"
    NIXDEV_UPDATE_NIX_BIN="$TD/fakebin/nix"
    NIXDEV_UPDATE_TARGET_REV="${NIXDEV_UPDATE_TARGET_REV:-$REV_ND_NEW}"
    NIXDEV_UPDATE_RETRIES="${NIXDEV_UPDATE_RETRIES:-1}"
    NIXDEV_UPDATE_RETRY_DELAY=0
    NIXDEV_UPDATE_POLL_TRIES=3
    NIXDEV_UPDATE_POLL_DELAY=0
    NIXDEV_UPDATE_TEST_NEW_LOCK="$LOCK_DIR/new.json"
    FAKE_LOG="$FAKE_LOG"
    FAKE_TARGET_REV="$REV_ND_NEW"
  )
  local v
  for v in FAKE_MERGE_FAIL FAKE_PR_HEAD_SHA FAKE_PR_MERGEABLE FAKE_PR_STATE \
           FAKE_PR_MERGED FAKE_PR_HEAD_REF FAKE_PR_BASE_REF \
           FAKE_CHECK_MARKER FAKE_CHECK_RESULT FAKE_API_DOWN FAKE_API_FLAP; do
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

echo
if [ "$failures" -eq 0 ]; then
  echo 'PASS — update-nixdev-config regression tests hold.'
  exit 0
fi
echo "FAIL — $failures regression test(s) failed." >&2
exit 1