#!/usr/bin/env bash
#
# test-mango-default-session.sh — regression tests for the conditional
# greetd default login session (modules/nixos/mango-experiment.nix).
#
# Locks in:
#   A. flag on:  greetd default_session.command starts Mango through the
#                start-mango-uwsm UWSM wrapper (`uwsm start -e -D mango
#                mango.desktop`) — never a bare `mango` exec, never a
#                Hyprland session bundled into the same command — while the
#                Hyprland fallback entries stay selectable at login;
#   B. flag off: greetd default_session.command stays the unchanged
#                start-hyprland-uwsm wrapper (Hyprland remains the default).
#
# Pure-eval checks run against the real flake (flag-on from the host config,
# flag-off from a rebuilt system with the experiment flag forced off) in
# scripts/mango-default-session-regression.nix; the wrapper-script *content*
# (the UWSM path requirement) is additionally verified against the module
# sources, which is where the wrapper bodies live.
#
# Safe by construction: only evaluates the flake and greps source files;
# never activates anything, never enters Mango. Skips (exit 0) when nix is
# unavailable.
#
# Usage: scripts/test-mango-default-session.sh
# Exit:  0 = all regressions hold (or nix unavailable); 1 = one failed.

set -u

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0

fail() {
  failures=$((failures + 1))
  echo "FAIL  $*" >&2
}

pass() {
  echo "PASS  $*"
}

if ! command -v nix >/dev/null 2>&1; then
  echo "SKIP  nix not found; conditional default-session checks skipped"
  exit 0
fi

echo '== conditional greetd default session =='

out="$(nix eval --impure --raw --file "$repo_root/scripts/mango-default-session-regression.nix" 2>/tmp/mango-default-session-nix-err.$$)"
rc=$?
err="$(cat /tmp/mango-default-session-nix-err.$$ 2>/dev/null || true)"
rm -f /tmp/mango-default-session-nix-err.$$

if [ "$rc" -ne 0 ]; then
  fail "nix eval of mango-default-session-regression.nix failed (rc=$rc):"
  echo "$err" | sed 's/^/    /' >&2
  exit 1
fi

if [ "$out" = "PASS" ]; then
  pass "flag-on Mango default and flag-off Hyprland default hold (pure-eval checks)"
else
  fail "regression checks failed: $out"
  exit 1
fi

# --- UWSM path guard (wrapper script content) ------------------------------
#
# The uwsm invocation is hidden inside the writeShellScript wrapper, so the
# pure-eval checks above cannot see it; verify the module sources keep the
# documented UWSM path and never exec the mango binary directly.

mango_module="$repo_root/modules/nixos/mango-experiment.nix"
hyprland_module="$repo_root/modules/nixos/hyprland.nix"

if grep -Fq 'exec ${pkgsUnstable.uwsm}/bin/uwsm' "$mango_module" &&
  grep -Fq 'start -e -D mango' "$mango_module" &&
  grep -Fq 'mango.desktop' "$mango_module"; then
  pass "mango wrapper source keeps the uwsm start -e -D mango mango.desktop path"
else
  fail "mango wrapper source lost the uwsm start -e -D mango mango.desktop path"
fi

if grep -Eq 'exec .*bin/mango([[:space:]]|$)' "$mango_module"; then
  fail "mango wrapper source execs the mango binary directly (UWSM bypass)"
else
  pass "mango wrapper source never execs a bare mango binary"
fi

if grep -Fq 'start -e -D Hyprland' "$hyprland_module" &&
  grep -Fq 'hyprland.desktop' "$hyprland_module"; then
  pass "hyprland wrapper source keeps the uwsm start -e -D Hyprland hyprland.desktop path"
else
  fail "hyprland wrapper source lost the uwsm start -e -D Hyprland hyprland.desktop path"
fi

echo
if [ "$failures" -eq 0 ]; then
  echo 'PASS — conditional default-session regressions hold.'
  exit 0
fi
exit 1