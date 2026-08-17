#!/usr/bin/env bash
#
# check.sh — repository-owned local validation (authoritative gate).
#
# Runs, in order:
#   1. static checks: shell syntax of the repo's scripts, YAML parse of
#      .github/*.yml and .github/dependabot.yml, JSON parse of
#      flake.lock and the node-tools lockfiles
#   2. `nix flake check`
#   3. a NON-ACTIVATING build of the metacube NixOS toplevel
#
# It never switches, tests, or activates the system. This is the local
# check every change — including Dependabot PRs — must pass before
# merge. CI (workflow_dispatch only) is an optional independent
# fallback, not a required check.
#
# Usage:
#   scripts/check.sh [--nix-build-only] [--skip-build] [-h|--help]
#
#   --nix-build-only  use plain
#                     `nix build .#nixosConfigurations.metacube.config.system.build.toplevel`
#                     instead of the established
#                     `sudo nixos-rebuild build --flake .#metacube`
#                     (for environments without usable sudo, e.g. CI
#                     runners or containers)
#   --skip-build      static checks + `nix flake check` only (no build)
#
# Exit codes: 0 = all checks passed; nonzero = first failing check.
#
# Static-check parsers: python3+PyYAML / yq / jq on PATH are used when
# present; otherwise `nix shell nixpkgs#<tool>` provides them. If no
# parser and no nix are available the step warns and is skipped (the
# flake steps below would fail in such an environment anyway).

set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

nix_build_only=0
skip_build=0

usage() {
  cat <<'EOF'
Usage: scripts/check.sh [--nix-build-only] [--skip-build] [-h|--help]

Local validation gate: static checks, `nix flake check`, and a
non-activating toplevel build. Never switches or activates the system.

  --nix-build-only  build with plain `nix build` instead of
                    `sudo nixos-rebuild build --flake .#metacube`
                    (for environments without usable sudo)
  --skip-build      static checks + `nix flake check` only
  -h, --help        show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --nix-build-only) nix_build_only=1; shift ;;
    --skip-build) skip_build=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

failures=0

# --- static checks --------------------------------------------------------

echo '==> Static checks'

echo '  shell syntax (bash -n):'
for f in scripts/*.sh; do
  [[ -f "$f" ]] || continue
  bash -n "$f"
  echo "    ok $f"
done

echo '  mango preflight regression tests:'
if ! scripts/test-mango-preflight.sh; then
  echo "    fail: scripts/test-mango-preflight.sh" >&2
  exit 1
fi
echo "    ok scripts/test-mango-preflight.sh"

echo '  mango client-window probe regression tests:'
if ! scripts/test-mango-probe.sh; then
  echo "    fail: scripts/test-mango-probe.sh" >&2
  exit 1
fi
echo "    ok scripts/test-mango-probe.sh"

echo '  mango blueman tray-applet regression tests:'
if ! scripts/test-mango-blueman.sh; then
  echo "    fail: scripts/test-mango-blueman.sh" >&2
  exit 1
fi
echo "    ok scripts/test-mango-blueman.sh"

echo '  mango default-session regression tests:'
if ! scripts/test-mango-default-session.sh; then
  echo "    fail: scripts/test-mango-default-session.sh" >&2
  exit 1
fi
echo "    ok scripts/test-mango-default-session.sh"

yaml_parser=""
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  yaml_parser="python3"
elif command -v yq >/dev/null 2>&1; then
  yaml_parser="yq"
elif command -v nix >/dev/null 2>&1; then
  yaml_parser="nix-shell-yq"
fi

echo '  YAML parse:'
mapfile -t yaml_files < <(find .github -maxdepth 2 \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null | sort)
if ((${#yaml_files[@]} > 0)); then
  case "$yaml_parser" in
    python3)
      python3 - "${yaml_files[@]}" <<'EOF'
import sys, yaml
for f in sys.argv[1:]:
    with open(f) as fh:
        yaml.safe_load(fh)
    print(f"    ok {f}")
EOF
      ;;
    yq)
      for f in "${yaml_files[@]}"; do
        yq eval . "$f" >/dev/null
        echo "    ok $f"
      done
      ;;
    nix-shell-yq)
      nix shell nixpkgs#yq-go -c bash -c '
        for f in "$@"; do
          yq eval . "$f" >/dev/null || exit 1
          echo "    ok $f"
        done
      ' _ "${yaml_files[@]}"
      ;;
    *)
      echo "    warn: no YAML parser available (python3/PyYAML, yq, or nix); skipping"
      ;;
  esac
fi

json_parser=""
if command -v jq >/dev/null 2>&1; then
  json_parser="jq"
elif command -v nix >/dev/null 2>&1; then
  json_parser="nix-shell-jq"
fi

echo '  JSON parse:'
json_files=(flake.lock home/firstmate/node-tools/package.json home/firstmate/node-tools/package-lock.json)
existing_json=()
for f in "${json_files[@]}"; do
  [[ -f "$f" ]] && existing_json+=("$f")
done
if ((${#existing_json[@]} > 0)); then
  case "$json_parser" in
    jq)
      for f in "${existing_json[@]}"; do
        jq empty "$f"
        echo "    ok $f"
      done
      ;;
    nix-shell-jq)
      nix shell nixpkgs#jq -c bash -c '
        for f in "$@"; do
          jq empty "$f" || exit 1
          echo "    ok $f"
        done
      ' _ "${existing_json[@]}"
      ;;
    *)
      echo "    warn: no JSON parser available (jq or nix); skipping"
      ;;
  esac
fi

# --- flake check ----------------------------------------------------------

echo '==> nix flake check'
nix flake check

# --- non-activating build -------------------------------------------------

if [[ "$skip_build" == 1 ]]; then
  echo '==> Build skipped (--skip-build)'
else
  echo '==> Building NixOS toplevel (never activates or switches)'
  if [[ "$nix_build_only" == 1 ]] || ! command -v sudo >/dev/null 2>&1; then
    echo '    nix build .#nixosConfigurations.metacube.config.system.build.toplevel'
    nix build .#nixosConfigurations.metacube.config.system.build.toplevel
  else
    echo '    sudo nixos-rebuild build --flake .#metacube'
    sudo nixos-rebuild build --flake .#metacube
  fi
fi

echo
echo 'PASS — local validation complete; nothing was activated or switched.'
