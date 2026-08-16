#!/usr/bin/env bash
#
# test-mango-probe.sh — regression tests for the bounded client-window
# polling in scripts/mango-probe-lib.sh (used by
# validate-mango-session.sh --launch-apps).
#
# Locks in the probe fix from the scout diagnosis
# (data/nixos-mango-core-app-probe-scout/report.md): the core-app probe
# took ONE `mmsg get all-clients` snapshot after 3 s and then killed the
# app, so cold-starting Firefox (XWayland) and Thunar windows could never
# map in time — two proven probe false negatives, not desktop defects.
# wait_for_client now polls every second for up to 30 s (first check
# still at 3 s, so fast apps still pass in one check) and the app is
# terminated only after a confirmed match or the timeout, with the last
# client snapshot and the app's captured stderr printed on timeout.
#
# Fixtures (all deterministic, no desktop involved):
#   fast       client visible on the first snapshot            -> match
#   slow       client appears after several polls (~T=10 s)    -> match
#   never      client never appears                            -> timeout + diagnostics
#   xwayland   client with/without is_xwayland == true         -> match / no match
#              (the real Mango XWayland predicate is preserved)
#   appid      marker matched via appid instead of title       -> match
#
# Safe by construction: `mmsg` and `sleep` are mocked as shell functions
# (hermetic — no shebang resolution, and they keep working when PATH is
# stripped for the no-jq case), so polling is instant and deterministic;
# the only real process is a short-lived `sleep` decoy standing in for
# the probed app. No desktop application is launched, stopped, or
# inspected.
#
# Usage: scripts/test-mango-probe.sh
# Exit:  0 = all regressions hold; 1 = at least one regression failed.
# XWayland predicate cases need a real jq on PATH and are SKIPped without
# one.

set -u

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
lib="$repo_root/scripts/mango-probe-lib.sh"
validator="$repo_root/scripts/validate-mango-session.sh"

failures=0

fail() {
  failures=$((failures + 1))
  echo "FAIL  $*" >&2
}

pass() {
  echo "PASS  $*"
}

# --- stubs for the helpers the lib expects from its consumers ----------------

ok() { printf 'OK-STUB   %s\n' "$*"; }
bad() { printf 'BAD-STUB  %s\n' "$*"; }
skip() { printf 'SKIP-STUB %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

. "$lib"

# --- mock fixtures -----------------------------------------------------------

mock_dir="$(mktemp -d "${TMPDIR:-/tmp}/mango-probe-mock.XXXXXX")"
mmsg_calls_file="$mock_dir/mmsg.calls"
out_file="$mock_dir/out"
err_file="$mock_dir/err"
decoy_pid=""
marker="mango-probe-fixture"

cleanup() {
  if [ -n "$decoy_pid" ]; then
    kill "$decoy_pid" >/dev/null 2>&1 || true
    wait "$decoy_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$mock_dir"
}
trap cleanup EXIT

# A short-lived real process standing in for the launched probe app. It
# must be a child of this shell so the lib's `wait` can reap it.
# `command` bypasses the mocked sleep() function below.
spawn_decoy() {
  command sleep 60 &
  decoy_pid=$!
}

cat > "$mock_dir/without.json" <<'EOF'
{"clients":[]}
EOF

cat > "$mock_dir/with.json" <<'EOF'
{"clients":[{"id":1,"pid":900,"title":"mango-probe-fixture","appid":"thunar","is_xwayland":false}]}
EOF

cat > "$mock_dir/with-xwayland.json" <<'EOF'
{"clients":[{"id":2,"pid":901,"title":"mango-probe-fixture — Mozilla Firefox","appid":"firefox","is_xwayland":true}]}
EOF

cat > "$mock_dir/with-xwayland-false.json" <<'EOF'
{"clients":[{"id":3,"pid":902,"title":"mango-probe-fixture — Mozilla Firefox","appid":"firefox","is_xwayland":false}]}
EOF

cat > "$mock_dir/with-appid.json" <<'EOF'
{"clients":[{"id":4,"pid":903,"title":"Generic Browser Window","appid":"mango-probe-fixture","is_xwayland":true}]}
EOF

cat > "$mock_dir/distractor.json" <<'EOF'
{"clients":[{"id":7,"pid":700,"title":"kitty","appid":"kitty","is_xwayland":false},{"id":8,"pid":701,"title":"mpv","appid":"mpv","is_xwayland":false}]}
EOF

# Mocked mmsg: serves an all-clients fixture. The matching client appears
# on the MOCK_APPEARS_AT-th call (1-based); earlier calls serve the
# MOCK_WITHOUT_JSON fixture. When MOCK_APP_PID is set, every pre-match
# call asserts the probed app is still alive — the original probe killed
# the app after its single 3 s snapshot, which this mock would catch.
mmsg() {
  local calls=0
  [ -f "$mmsg_calls_file" ] && read -r calls < "$mmsg_calls_file"
  calls=$((calls + 1))
  printf '%s\n' "$calls" > "$mmsg_calls_file"

  if [ -n "${MOCK_APP_PID:-}" ] && [ "$calls" -lt "${MOCK_APPEARS_AT:-1}" ]; then
    if ! kill -0 "$MOCK_APP_PID" 2>/dev/null; then
      echo "mock-mmsg: app pid $MOCK_APP_PID died before its client appeared (premature kill)" >&2
      return 3
    fi
  fi

  if [ "$calls" -ge "${MOCK_APPEARS_AT:-1}" ]; then
    content="$(<"${MOCK_WITH_JSON:?}")"
  else
    content="$(<"${MOCK_WITHOUT_JSON:?}")"
  fi
  printf '%s\n' "$content"
}

# Mocked sleep: no-op, so polling time is simulated and tests stay
# instant and deterministic regardless of wall-clock scheduling.
sleep() {
  return 0
}

# set_fixture <appears-at-call> <with-json> [without-json] [app-pid]
set_fixture() {
  MOCK_APPEARS_AT="$1"
  MOCK_WITH_JSON="$2"
  MOCK_WITHOUT_JSON="${3:-$mock_dir/without.json}"
  MOCK_APP_PID="${4:-}"
  : > "$mmsg_calls_file"
}

# run_wait <marker> <appears-at-call> <with-json> [--without-json FILE] [wait_for_client args...]
# Runs wait_for_client with the fixture configured; stdout/stderr go to
# $out_file/$err_file. --without-json sets the pre-match snapshot fixture
# (default: empty client list).
run_wait() {
  local marker="$1"
  local appears_at="$2"
  local with_json="$3"
  shift 3
  local without_json="$mock_dir/without.json"
  local wait_args=()

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --without-json)
        without_json="$2"
        shift 2
        ;;
      *)
        wait_args+=("$1")
        shift
        ;;
    esac
  done

  set_fixture "$appears_at" "$with_json" "$without_json"
  wait_for_client "$marker" "${wait_args[@]}" >"$out_file" 2>"$err_file"
}

mmsg_calls() {
  if [ -f "$mmsg_calls_file" ]; then
    cat "$mmsg_calls_file"
  else
    echo 0
  fi
}

# --- fast client -------------------------------------------------------------

echo '== fast client (visible on the first snapshot) =='

if run_wait "$marker" 1 "$mock_dir/with.json"; then
  pass "fast client matches on the first snapshot"
else
  fail "fast client: expected match, rc=$?"
fi
if [ "$(mmsg_calls)" = "1" ]; then
  pass "fast path retained: a visible client passes in a single snapshot"
else
  fail "fast client: expected exactly 1 mmsg call, got $(mmsg_calls)"
fi

# --- slow client -------------------------------------------------------------

echo '== slow client (appears after several polls) =='

# The 8th snapshot happens at waited = 8 + 2 = ~T=10 s: the original
# single-3-s-snapshot probe would have failed and killed the app before
# this window mapped.
if run_wait "$marker" 8 "$mock_dir/with.json"; then
  pass "slow client (appears at ~T=10 s) matches within the 30 s poll"
else
  fail "slow client: expected match, rc=$?"
fi
if [ "$(mmsg_calls)" = "8" ]; then
  pass "polling stops exactly at the confirmed match ($(mmsg_calls) calls)"
else
  fail "slow client: expected 8 mmsg calls, got $(mmsg_calls)"
fi

# --- never-appearing client --------------------------------------------------

echo '== never-appearing client (timeout + diagnostics) =='

if run_wait "$marker" 999 "$mock_dir/with.json" --without-json "$mock_dir/distractor.json" --timeout 5; then
  fail "never-appearing client: expected timeout"
else
  rc=$?
  if [ "$rc" -eq 1 ]; then
    pass "never-appearing client times out with exit 1"
  else
    fail "never-appearing client: expected exit 1, got $rc"
  fi
fi
if grep -Fq "no client matching '$marker' appeared within 5s" "$err_file"; then
  pass "timeout verdict names the marker and the bound"
else
  fail "timeout verdict missing from diagnostics"
fi
if grep -Fq "kitty" "$err_file" && grep -Fq "mpv" "$err_file"; then
  pass "timeout diagnostics list the last snapshot's clients"
else
  fail "last-snapshot client list missing from diagnostics"
fi

# --- XWayland predicate ------------------------------------------------------

echo '== XWayland predicate (real is_xwayland == true) =='

if have jq; then
  if run_wait "$marker" 1 "$mock_dir/with-xwayland.json" --xwayland; then
    pass "XWayland client (is_xwayland true) matches in xwayland mode"
  else
    fail "XWayland client: expected match, rc=$?"
  fi

  if run_wait "$marker" 1 "$mock_dir/with-xwayland-false.json" --xwayland; then
    fail "non-XWayland client matched in xwayland mode (predicate weakened)"
  else
    pass "non-XWayland client rejected in xwayland mode (real predicate preserved)"
  fi

  if run_wait "$marker" 1 "$mock_dir/with-xwayland-false.json"; then
    pass "the same client still matches in window mode (marker is present)"
  else
    fail "non-XWayland client did not match in window mode"
  fi

  if run_wait "$marker" 1 "$mock_dir/with-appid.json" --xwayland; then
    pass "marker matched via appid with is_xwayland true"
  else
    fail "appid-only match: expected match, rc=$?"
  fi
else
  echo "SKIP  XWayland predicate cases need jq on PATH"
fi

# --- usage errors ------------------------------------------------------------

echo '== usage errors =='

if run_wait "" 1 "$mock_dir/with.json"; then
  fail "empty marker should be a usage error"
else
  rc=$?
  if [ "$rc" -eq 2 ]; then
    pass "missing marker is a usage error (exit 2)"
  else
    fail "missing marker: expected exit 2, got $rc"
  fi
fi

# --- probe_client_window process lifecycle -----------------------------------

echo '== probe_client_window process lifecycle =='

# run_probe <appears-at> <with-json> <without-json> <decoy-pid> [probe args...]
run_probe() {
  local appears_at="$1"
  local with_json="$2"
  local without_json="$3"
  local app_pid="$4"
  shift 4

  set_fixture "$appears_at" "$with_json" "$without_json" "$app_pid"
  probe_client_window "$@" >"$out_file" 2>"$err_file"
}

# slow fixture + real decoy: the app must stay alive while polling and be
# killed only after the confirmed match.
spawn_decoy
run_probe 8 "$mock_dir/with.json" "$mock_dir/without.json" "$decoy_pid" \
  "probe-app" "$marker" "$decoy_pid" stop window
if grep -q 'OK-STUB' "$out_file"; then
  pass "slow app is not killed early: matched only after the poll (mock liveness check passed)"
else
  fail "slow app: expected OK verdict"
  sed 's/^/    /' "$out_file" "$err_file"
fi
if kill -0 "$decoy_pid" 2>/dev/null; then
  fail "slow app still alive after cleanup=stop"
else
  pass "app terminated only after the confirmed match"
fi
decoy_pid=""

# never fixture + captured stderr: BAD verdict after the timeout, and the
# diagnostics include the app's captured stderr.
printf 'Gdk-WARNING **: window failed to map in time\n' > "$mock_dir/app.stderr"
spawn_decoy
run_probe 999 "$mock_dir/with.json" "$mock_dir/distractor.json" "$decoy_pid" \
  "probe-app" "$marker" "$decoy_pid" stop window "$mock_dir/app.stderr"
if grep -q 'BAD-STUB' "$out_file"; then
  pass "never-appearing app gets a BAD verdict after the timeout"
else
  fail "never-appearing app: expected BAD verdict"
  sed 's/^/    /' "$out_file" "$err_file"
fi
if grep -Fq 'window failed to map in time' "$err_file"; then
  pass "timeout diagnostics include the captured app stderr"
else
  fail "captured app stderr missing from timeout diagnostics"
fi
if kill -0 "$decoy_pid" 2>/dev/null; then
  fail "never-appearing app still alive after cleanup=stop"
else
  pass "app terminated after the timeout verdict"
fi
decoy_pid=""

# cleanup=keep: the app survives the probe for the caller to stop later.
spawn_decoy
run_probe 1 "$mock_dir/with.json" "$mock_dir/without.json" "$decoy_pid" \
  "probe-app" "$marker" "$decoy_pid" keep window
if kill -0 "$decoy_pid" 2>/dev/null; then
  pass "cleanup=keep leaves the app running after the match"
  stop_probe_process "$decoy_pid"
else
  fail "cleanup=keep killed the app"
fi
decoy_pid=""

# xwayland mode without jq: SKIPped (the real predicate needs jq) and the
# app is cleaned up, mirroring the original probe's guard. PATH is
# stripped of everything (the mocks are functions, so only builtins are
# needed) to prove jq is genuinely unreachable.
spawn_decoy
(
  MOCK_APPEARS_AT=1
  MOCK_WITH_JSON="$mock_dir/with-xwayland.json"
  MOCK_WITHOUT_JSON="$mock_dir/without.json"
  MOCK_APP_PID="$decoy_pid"
  PATH="$mock_dir"
  export PATH
  probe_client_window "probe-app" "$marker" "$decoy_pid" stop xwayland >"$out_file" 2>"$err_file"
)
if grep -q 'SKIP-STUB' "$out_file"; then
  pass "xwayland mode without jq is SKIPped, not faked"
else
  fail "xwayland mode without jq: expected SKIP verdict"
  sed 's/^/    /' "$out_file" "$err_file"
fi
if kill -0 "$decoy_pid" 2>/dev/null; then
  fail "skip path left the app running"
else
  pass "skip path still cleans up the launched app"
fi
decoy_pid=""

# --- structural regression locks ---------------------------------------------

echo '== structural regression locks =='

if grep -Fq 'mango-probe-lib.sh' "$validator"; then
  pass "validate-mango-session.sh sources the shared probe lib"
else
  fail "validate-mango-session.sh does not source mango-probe-lib.sh"
fi

if grep -Fn 'sleep 3' "$validator" >/dev/null; then
  fail "validate-mango-session.sh still has the single 'sleep 3' snapshot"
else
  pass "no single 'sleep 3' snapshot remains in validate-mango-session.sh"
fi

if grep -Fq 'wait_for_client()' "$lib" &&
  grep -Fq 'timeout=30' "$lib" &&
  grep -Fq 'first_delay=3' "$lib"; then
  pass "lib polls every second up to 30 s with the 3 s fast path"
else
  fail "lib is missing the bounded poll (timeout/first-delay defaults)"
fi

if grep -Fq 'is_xwayland == true' "$lib"; then
  pass "real XWayland predicate (is_xwayland == true) preserved"
else
  fail "XWayland predicate changed"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "PASS — mango client-window probe regressions hold"
  exit 0
else
  echo "FAIL — $failures mango client-window probe regression(s) failed" >&2
  exit 1
fi
