#!/usr/bin/env bash
#
# test-mango-blueman.sh — regression tests for the Mango-only suppression of
# the legacy blueman tray applet (home/modules/experiment.nix).
#
# Locks in:
#   A. flag on:  ~/.config/autostart/blueman.desktop shadows the system XDG
#                autostart entry (systemd >= 260 turns NotShowIn=mango into
#                an ExecCondition= evaluated at service start, so the applet
#                is skipped exactly when XDG_CURRENT_DESKTOP contains mango);
#   B. flag off: no autostart shadow exists, so the system entry (and the
#                applet in every session) is unchanged.
#
# The checks are evaluated against the real flake (flag-on state from the
# host config, flag-off state from a rebuilt system with the experiment
# flag forced off) — see scripts/mango-blueman-regression.nix.
#
# Safe by construction: only evaluates the flake; never activates anything,
# starts or stops services, or enters Mango. Skips (exit 0) when nix is
# unavailable.
#
# Usage: scripts/test-mango-blueman.sh
# Exit:  0 = all regressions hold (or nix unavailable); 1 = a regression failed.

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
  echo "SKIP  nix not found; blueman tray-applet regression checks skipped"
  exit 0
fi

echo '== blueman tray-applet autostart shadow =='

out="$(nix eval --impure --raw --file "$repo_root/scripts/mango-blueman-regression.nix" 2>/tmp/mango-blueman-nix-err.$$)"
rc=$?
err="$(cat /tmp/mango-blueman-nix-err.$$ 2>/dev/null || true)"
rm -f /tmp/mango-blueman-nix-err.$$

if [ "$rc" -ne 0 ]; then
  fail "nix eval of mango-blueman-regression.nix failed (rc=$rc):"
  echo "$err" | sed 's/^/    /' >&2
  exit 1
fi

if [ "$out" = "PASS" ]; then
  pass "flag-on shadow (NotShowIn=mango, Exec=blueman-applet) and flag-off absence hold"
else
  fail "regression checks failed: $out"
  exit 1
fi

echo
if [ "$failures" -eq 0 ]; then
  echo 'PASS — blueman tray-applet regressions hold.'
  exit 0
fi
exit 1
