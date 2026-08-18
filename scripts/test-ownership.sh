#!/usr/bin/env bash
#
# test-ownership.sh — regression tests for the shared-Firstmate toolchain
# ownership boundary and the opt-in FM Dependabot sweep timer.
#
# Locks in (scripts/ownership-regression.nix holds the pure-eval half):
#   A. this consumer declares NO treehouse/herdr/noMistakes flake inputs,
#      no local package-building modules (treehouse.nix/herdr.nix/
#      firstmate.nix), no update-no-mistakes.sh, and no duplicate
#      firstmate node-tools pin set — shared toolchain pins are
#      nixdev-config-owned and wired via
#      `nixdev-config.homeManagerModules.firstmateTools` with the
#      exported treehouse package; MetaCube keeps the repo-root
#      treehouse.toml capacity policy and its Herdr-backend choice;
#   B. the opt-in Dependabot sweep timer/service
#      (home/modules/firstmate-timer.nix) is enabled for MetaCube and
#      defined exactly (FM_HOME=%h/firstmate, WorkingDirectory=%h/
#      firstmate, ConditionPathExists on the private home's command,
#      hourly Persistent timer with a small randomized delay), while
#      remaining off by default so the standalone laptop profile never
#      gets it.
#
# Safe by construction: only evaluates the flake and greps source files;
# never activates anything.
#
# Usage: scripts/test-ownership.sh
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
  echo "SKIP  nix not found; ownership/timer checks skipped"
  exit 0
fi

echo '== shared-Firstmate ownership boundary'

flake_nix="$repo_root/flake.nix"
linhnt_nix="$repo_root/home/linhnt.nix"
dev_nix="$repo_root/home/modules/dev.nix"
timer_module="$repo_root/home/modules/firstmate-timer.nix"

# Source-level guarantees the pure-eval half also covers, kept here so a
# failure message points at the exact file/line.
if ! grep -qE '^\s*treehouse\.url' "$flake_nix" &&
  ! grep -qE '^\s*herdr\.url' "$flake_nix" &&
  ! grep -qE '^\s*noMistakes' "$flake_nix"; then
  pass "flake.nix declares no treehouse/herdr/noMistakes inputs"
else
  fail "flake.nix still declares a toolchain input (treehouse/herdr/noMistakes)"
fi

if grep -Fq 'nixdev-config.homeManagerModules.firstmateTools' "$flake_nix" &&
  grep -Fq 'treehousePkg =' "$flake_nix" &&
  grep -Fq 'nixdev-config.packages.${system}.treehouse' "$flake_nix"; then
  pass "flake.nix consumes firstmateTools with the exported treehouse package"
else
  fail "flake.nix is not wired to nixdev-config's firstmateTools + treehousePkg"
fi

for gone in \
  "$repo_root/home/modules/treehouse.nix" \
  "$repo_root/home/modules/herdr.nix" \
  "$repo_root/home/modules/firstmate.nix" \
  "$repo_root/home/firstmate/node-tools/package.json" \
  "$repo_root/scripts/update-no-mistakes.sh"; do
  if [ ! -e "$gone" ]; then
    pass "removed: ${gone#$repo_root/}"
  else
    fail "still present: ${gone#$repo_root/}"
  fi
done

if grep -Fq 'enableHerdr = true' "$linhnt_nix"; then
  pass "home/linhnt.nix enables the pinned herdr (MetaCube Herdr backend)"
else
  fail "home/linhnt.nix does not enable nixdev.firstmate.enableHerdr"
fi

echo '== FM Dependabot sweep timer'

if [ -f "$timer_module" ] &&
  grep -Fq 'metacube.firstmate.fmDependabotSweep.enable' "$linhnt_nix"; then
  pass "timer module exists and MetaCube opts in"
else
  fail "timer module or MetaCube opt-in missing"
fi

if grep -Fq 'firstmateHome = "%h/firstmate"' "$timer_module" &&
  grep -Fq 'FM_HOME=' "$timer_module" &&
  grep -Fq 'WorkingDirectory = firstmateHome' "$timer_module" &&
  grep -Fq 'ConditionPathExists' "$timer_module" &&
  grep -Fq 'OnCalendar = "hourly"' "$timer_module" &&
  grep -Fq 'Persistent = true' "$timer_module" &&
  grep -Fq 'RandomizedDelaySec = "15m"' "$timer_module"; then
  pass "timer module carries the exact service/timer contract"
else
  fail "timer module lost part of the service/timer contract"
fi

# Pure-eval assertions against the real flake (ownership + timer shape +
# opt-in default).
out="$(nix eval --impure --raw --file "$repo_root/scripts/ownership-regression.nix" 2>/tmp/fm-ownership-nix-err.$$)"
rc=$?
err="$(cat /tmp/fm-ownership-nix-err.$$ 2>/dev/null || true)"
rm -f /tmp/fm-ownership-nix-err.$$

if [ "$rc" -ne 0 ]; then
  fail "nix eval of ownership-regression.nix failed (rc=$rc):"
  echo "$err" | sed 's/^/    /' >&2
  exit 1
fi

if [ "$out" = "PASS" ]; then
  pass "ownership boundary + timer definition hold (pure-eval checks)"
else
  fail "regression checks failed: $out"
  exit 1
fi

echo
if [ "$failures" -eq 0 ]; then
  echo 'PASS — ownership/timer regressions hold.'
  exit 0
fi
exit 1