#!/usr/bin/env bash
#
# test-mango-preflight.sh — regression tests for the --preflight context
# guards in validate-mango-session.sh.
#
# Locks in the fixes from the scout diagnosis
# (data/nixos-mango-preflight-fallback-scout/report.md):
#   A. the compositor check matches the wrapper-renamed Hyprland process
#      via its command line ('/bin/Hyprland'), not its comm name
#      (-x Hyprland, which can never match .Hyprland-wrapped);
#   B. --preflight rejects execution from inside a graphical session
#      instead of silently exempting the current session.
#
# Safe by construction: spawns only a short-lived `sleep` decoy and mocked
# pgrep/loginctl/systemctl fixtures on a private PATH. It never stops or
# starts services, enters Mango, switches the system, or needs a desktop.
#
# Usage: scripts/test-mango-preflight.sh
# Exit:  0 = all regressions hold; 1 = at least one regression failed.

set -u

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
script="$repo_root/scripts/validate-mango-session.sh"

failures=0

fail() {
  failures=$((failures + 1))
  echo "FAIL  $*" >&2
}

pass() {
  echo "PASS  $*"
}

mock_dir=""
decoy_pid=""

cleanup() {
  if [ -n "$decoy_pid" ]; then
    kill "$decoy_pid" >/dev/null 2>&1 || true
    wait "$decoy_pid" >/dev/null 2>&1 || true
  fi
  if [ -n "$mock_dir" ]; then
    rm -rf "$mock_dir"
  fi
}
trap cleanup EXIT

# --- Regression 1: wrapper-renamed Hyprland process detection --------------

echo '== wrapper-renamed Hyprland detection =='

if command -v pgrep >/dev/null 2>&1; then
  # Hyprland 0.55.x renames itself to .Hyprland-wrapped; the kernel
  # truncates comm to 15 chars (.Hyprland-wrapp), so `pgrep -x Hyprland`
  # can never match the running compositor. Simulate the renamed process
  # with `exec -a`: argv[0] carries the Hyprland store path while comm
  # stays `bash` (a bare `exec -a ... sleep` would trip multi-call
  # dispatch on argv[0], so bash itself stays alive).
  bash -c 'exec -a /nix/store/fake-hyprland-0.55.4/bin/Hyprland bash -c "while :; do sleep 1; done"' &
  decoy_pid=$!
  sleep 0.3

  if pgrep -u "$(id -u)" -x Hyprland >/dev/null 2>&1; then
    fail "comm-name pattern 'pgrep -x Hyprland' matched the renamed-process decoy"
  else
    pass "comm-name pattern misses the wrapper-renamed decoy (the original defect)"
  fi

  matched="$(pgrep -u "$(id -u)" -f '/bin/Hyprland' 2>/dev/null || true)"
  if printf '%s\n' "$matched" | grep -qw "$decoy_pid"; then
    pass "cmdline pattern 'pgrep -f /bin/Hyprland' finds the wrapper-renamed decoy"
  else
    fail "cmdline pattern did not find the wrapper-renamed decoy (matched: $matched)"
  fi

  kill "$decoy_pid" >/dev/null 2>&1 || true
  wait "$decoy_pid" >/dev/null 2>&1 || true
  decoy_pid=""
else
  echo "SKIP  pgrep not available; wrapper-renamed detection not exercised"
fi

# Lock the fix into the script: the compositor check must use the cmdline
# pattern and must not regress to comm-name matching.
if grep -Fq "pgrep -u \"\$uid\" -f '/bin/Hyprland'" "$script"; then
  pass "validate-mango-session.sh uses the '/bin/Hyprland' cmdline pattern"
else
  fail "validate-mango-session.sh does not use the '/bin/Hyprland' cmdline pattern"
fi

if grep -Fq 'pgrep -u "$uid" -x Hyprland' "$script"; then
  fail "validate-mango-session.sh still has the comm-name 'pgrep -x Hyprland' check"
else
  pass "validate-mango-session.sh has no comm-name 'pgrep -x Hyprland' check"
fi

# --- Regression 2: --preflight graphical-session context guard -------------

echo '== --preflight graphical-session context guard =='

mock_dir="$(mktemp -d "${TMPDIR:-/tmp}/mango-preflight-mock.XXXXXX")"

cat > "$mock_dir/pgrep" <<'EOF'
#!/usr/bin/env bash
# No compositor running in the mocked preflight context.
exit 1
EOF

cat > "$mock_dir/systemctl" <<'EOF'
#!/usr/bin/env bash
# Healthy user manager, no fallback service active.
[ "${1:-}" = "--user" ] && shift
case "${1:-}" in
  show-environment) exit 0 ;;
  *) exit 1 ;;
esac
EOF

cat > "$mock_dir/loginctl" <<'EOF'
#!/usr/bin/env bash
# Mocked loginctl: session Type/Desktop come from MOCK_SESSION_TYPE and
# MOCK_SESSION_DESKTOP; list-sessions emits only the current session
# (session 42), which the script exempts.
case "${1:-}" in
  list-sessions)
    echo "42 1000 testuser seat0 9999 tty2 active tty"
    ;;
  show-session)
    shift
    prop=""
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "-p" ] && [ "$#" -ge 2 ]; then
        prop="$2"
        shift 2
      else
        shift
      fi
    done
    case "$prop" in
      Type) printf '%s\n' "${MOCK_SESSION_TYPE:-tty}" ;;
      Desktop) printf '%s\n' "${MOCK_SESSION_DESKTOP:-}" ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF

chmod +x "$mock_dir"/*

run_preflight() { # session-id mock-type mock-desktop
  env XDG_SESSION_ID="$1" USER=testuser \
    MOCK_SESSION_TYPE="$2" MOCK_SESSION_DESKTOP="$3" \
    PATH="$mock_dir:$PATH" "$script" --preflight >"$mock_dir/out" 2>&1
  return $?
}

# A preflight run from inside a graphical session must be rejected with
# exit 2 and a fresh-VT message, before any sequential check runs.
run_preflight 99 wayland Hyprland
rc=$?
if [ "$rc" -eq 2 ] && grep -q "fresh VT" "$mock_dir/out"; then
  pass "preflight inside a Hyprland/wayland session is rejected (exit 2, fresh-VT message)"
else
  fail "preflight inside a Hyprland/wayland session: expected exit 2 + fresh-VT message, got rc=$rc"
  sed 's/^/    /' "$mock_dir/out"
fi
if grep -q "Sequential-session boundary" "$mock_dir/out"; then
  fail "preflight guard did not stop before the sequential checks"
else
  pass "preflight guard stops before the sequential checks"
fi

run_preflight 98 x11 ""
rc=$?
if [ "$rc" -eq 2 ] && grep -q "fresh VT" "$mock_dir/out"; then
  pass "preflight inside an x11 session is rejected (exit 2, fresh-VT message)"
else
  fail "preflight inside an x11 session: expected exit 2 + fresh-VT message, got rc=$rc"
  sed 's/^/    /' "$mock_dir/out"
fi

run_preflight 97 tty Hyprland
rc=$?
if [ "$rc" -eq 2 ] && grep -q "fresh VT" "$mock_dir/out"; then
  pass "preflight with Desktop=Hyprland is rejected (exit 2, fresh-VT message)"
else
  fail "preflight with Desktop=Hyprland: expected exit 2 + fresh-VT message, got rc=$rc"
  sed 's/^/    /' "$mock_dir/out"
fi

# A fresh-VT context (non-graphical current session) must still pass the
# guard and complete the full preflight cleanly.
run_preflight 42 tty ""
rc=$?
if [ "$rc" -eq 0 ] &&
  grep -q "no Hyprland compositor is running" "$mock_dir/out" &&
  grep -q "no other same-user graphical session is active" "$mock_dir/out" &&
  grep -q "fallback Hyprland services are inactive" "$mock_dir/out"; then
  pass "fresh-VT preflight still passes all sequential checks"
else
  fail "fresh-VT preflight: expected exit 0 with three PASS lines, got rc=$rc"
  sed 's/^/    /' "$mock_dir/out"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo "PASS — mango preflight regressions hold"
  exit 0
else
  echo "FAIL — $failures mango preflight regression(s) failed" >&2
  exit 1
fi
