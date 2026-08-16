#!/usr/bin/env bash
#
# validate-mango-session.sh — Phase 1 validation checklist for the
# MangoWM + Noctalia experiment (docs/mango-noctalia-experiment.md).
#
# Two modes:
#
#   --static [CONFIG_DIR]
#       Validate the generated config files without a running session.
#       CONFIG_DIR defaults to ~/.config; only the noctalia config.toml and
#       the MetaCube palette are validated here (Mango config.conf has no
#       offline validator at 0.15.6 — it is checked at runtime via hot
#       reload + the mmsg probes below).
#
#   (default, run inside the Mango session)
#       Full Phase-1 checklist: Mango IPC, Noctalia IPC, lock probe,
#       suspend/resume probe (opt-in), core apps, screenshot/clipboard,
#       screen-sharing portal probe, and a memory footprint report.
#
# Flags:
#   --lock-loop N     lock/unlock cycle probe for Noctalia #3848; you must
#                     unlock manually each round (N=20 for the gate probe)
#   --suspend-probe   lock, suspend, verify the session survives resume
#                     (Mango #1017); the machine actually suspends
#   --launch-apps     launch kitty/firefox and verify they appear via mmsg
#   --footprint       print RSS of mango/noctalia for the footprint criterion
#
# Exit status: 0 = all executed checks passed; 1 = at least one failed;
# skipped checks never fail the run.
#
# Requires: bash, coreutils. Session checks additionally require mmsg,
# noctalia, and the probed tools (missing tools are reported as SKIP).

set -u

PASS=0
FAIL=0
SKIP=0

ok() {
  PASS=$((PASS + 1))
  printf 'PASS  %s\n' "$*"
}

bad() {
  FAIL=$((FAIL + 1))
  printf 'FAIL  %s\n' "$*"
}

skip() {
  SKIP=$((SKIP + 1))
  printf 'SKIP  %s\n' "$*"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

require_tool() { # name binary
  if have "$2"; then
    return 0
  fi
  skip "tool '$2' not found on PATH ($1)"
  return 1
}

section() {
  printf '\n== %s ==\n' "$*"
}

# --- Static config validation ------------------------------------------------

static_checks() {
  local config_dir="${1:-$HOME/.config}"
  local noctalia_config="$config_dir/noctalia/config.toml"
  local palette="$config_dir/noctalia/palettes/MetaCube.json"

  section "Static config validation ($config_dir)"

  if require_tool "Noctalia config validator" "noctalia"; then
    if [ -f "$noctalia_config" ]; then
      if noctalia config validate "$noctalia_config" >/tmp/noctalia-validate.log 2>&1; then
        ok "noctalia config validate: $noctalia_config"
      else
        bad "noctalia config validate failed: $noctalia_config"
        sed 's/^/      /' /tmp/noctalia-validate.log
      fi
    else
      skip "noctalia config.toml not found: $noctalia_config"
    fi
  fi

  if [ -f "$palette" ]; then
    # The palette is JSON consumed by the shell; beta.7 has no offline
    # validator for it, so at least confirm it parses as JSON.
    if command -v jq >/dev/null 2>&1; then
      if jq -e '.dark and .dark.mPrimary' "$palette" >/dev/null 2>&1; then
        ok "palette parses and has a dark variant with mPrimary: $palette"
      else
        bad "palette is not valid palette JSON: $palette"
      fi
    elif have "noctalia"; then
      skip "jq not found; palette JSON not checked"
    fi
  else
    skip "palette not found: $palette"
  fi
}

# --- Session checks ----------------------------------------------------------

mmsg_checks() {
  section "Mango IPC (mmsg)"

  require_tool "mmsg" "mmsg" || return

  local out
  out="$(mmsg get version 2>&1)" || {
    bad "mmsg get version failed: $out"
    return
  }
  ok "mmsg get version: $out"

  if mmsg get all-monitors >/dev/null 2>&1; then
    ok "mmsg get all-monitors"
  else
    bad "mmsg get all-monitors failed"
  fi

  if mmsg get all-tags >/dev/null 2>&1; then
    ok "mmsg get all-tags (workspace state for Noctalia)"
  else
    bad "mmsg get all-tags failed"
  fi

  if out="$(mmsg get keymode 2>&1)" && [ -n "$out" ]; then
    ok "mmsg get keymode: $out"
  else
    bad "mmsg get keymode failed"
  fi
}

noctalia_ipc_checks() {
  section "Noctalia IPC"

  require_tool "noctalia" "noctalia" || return

  local out
  out="$(noctalia msg status 2>&1)" || {
    bad "noctalia msg status failed (is the shell running?): $out"
    return
  }
  ok "noctalia msg status: $out"

  if noctalia msg panel-toggle launcher >/dev/null 2>&1; then
    ok "noctalia msg panel-toggle launcher"
  else
    bad "noctalia msg panel-toggle launcher failed"
  fi
  sleep 1
  if noctalia msg panel-close launcher >/dev/null 2>&1; then
    ok "noctalia msg panel-close launcher"
  else
    bad "noctalia msg panel-close launcher failed"
  fi
}

lock_probe() { # count
  local count="$1"
  local i

  section "Lock/unlock probe (Noctalia #3848, $count cycles)"

  require_tool "noctalia" "noctalia" || return

  echo "      The lock screen needs your password each round."
  for i in $(seq 1 "$count"); do
    printf '      cycle %s/%s: locking... ' "$i" "$count"
    noctalia msg session lock >/dev/null 2>&1
    echo "unlock it now, then press Enter"
    read -r _
    if noctalia msg status >/dev/null 2>&1; then
      echo "      cycle $i ok"
    else
      bad "shell did not respond after unlock at cycle $i"
      return
    fi
  done
  ok "lock/unlock x$count without hangs"
}

suspend_probe() {
  section "Suspend/resume probe (Mango #1017)"

  require_tool "noctalia" "noctalia" || return
  require_tool "systemctl" "systemctl" || return

  echo "      Locking, then suspending for ~20s; wake up and unlock manually."
  noctalia msg session lock >/dev/null 2>&1
  sleep 1
  systemctl suspend
  echo "      Resumed. Unlock the screen, then press Enter"
  read -r _

  local out
  out="$(mmsg get version 2>&1)" || {
    bad "mmsg does not respond after resume (Mango #1017 repro)"
    return
  }
  ok "mmsg responds after resume: $out"

  if noctalia msg status >/dev/null 2>&1; then
    ok "noctalia responds after resume"
  else
    bad "noctalia does not respond after resume"
  fi
}

core_apps_checks() {
  section "Core apps"

  for app in kitty firefox thunar mpv zathura; do
    if have "$app"; then
      ok "app available: $app"
    else
      skip "app not on PATH: $app"
    fi
  done

  if [ "${LAUNCH_APPS:-0}" = "1" ]; then
    require_tool "mmsg" "mmsg" || return
    if have "kitty"; then
      kitty --class validate-mango-probe >/dev/null 2>&1 &
      local kitty_pid=$!
      sleep 3
      if mmsg get all-clients 2>/dev/null | grep -q "validate-mango-probe"; then
        ok "launched kitty appears in mmsg get all-clients"
      else
        bad "launched kitty not visible via mmsg"
      fi
      kill "$kitty_pid" >/dev/null 2>&1
    else
      skip "launch probe: kitty not found"
    fi
  fi
}

screenshot_clipboard_checks() {
  section "Screenshot / clipboard"

  if have "grim" && have "slurp"; then
    local shot
    shot="$(mktemp --suffix=.png)"
    if grim "$shot" 2>/dev/null && [ -s "$shot" ] &&
      head -c 8 "$shot" | grep -q "PNG"; then
      ok "grim fullscreen screenshot produced a PNG"
    else
      bad "grim screenshot failed (wlr-screencopy probe)"
    fi
    rm -f "$shot"
  else
    skip "grim/slurp not on PATH"
  fi

  if have "wl-copy" && have "wl-paste"; then
    local payload="mango-noctalia-probe-$$"
    if wl-copy "$payload" && [ "$(wl-paste)" = "$payload" ]; then
      ok "wl-copy/wl-paste roundtrip (wlr-data-control probe)"
    else
      bad "wl-copy/wl-paste roundtrip failed"
    fi
  else
    skip "wl-copy/wl-paste not on PATH"
  fi
}

screen_share_probe() {
  section "Screen sharing (Mango #1162)"

  # Non-interactive probe: the xdg-desktop-portal ScreenCast interface must
  # be reachable and served by the wlr backend wired by programs.mango.
  # The actual OBS share session stays a manual probe.
  if have "busctl"; then
    local version
    version="$(
      busctl --user get-property \
        org.freedesktop.portal.Desktop \
        /org/freedesktop/portal/desktop \
        org.freedesktop.portal.ScreenCast version 2>&1
    )" || {
      bad "ScreenCast portal not reachable: $version"
      return
    }
    ok "ScreenCast portal reachable: $(echo "$version" | tr -s ' ')"
  else
    skip "busctl not on PATH"
  fi

  if have "obs"; then
    echo "      Manual probe: start OBS and share the screen once."
  else
    skip "obs not on PATH (manual screen-share probe pending)"
  fi
}

footprint_report() {
  section "Memory footprint"

  local pid rss_kb total_kb=0 found=0

  for name in mango noctalia; do
    found=0
    for pid in $(pgrep -x "$name" 2>/dev/null); do
      rss_kb="$(awk '/VmRSS/ {print $2}' "/proc/$pid/status" 2>/dev/null)"
      if [ -n "$rss_kb" ]; then
        printf '      %s (pid %s): %s KiB RSS\n' "$name" "$pid" "$rss_kb"
        total_kb=$((total_kb + rss_kb))
        found=1
      fi
    done
    [ "$found" = "0" ] && skip "no running process named $name"
  done

  [ "$total_kb" -gt 0 ] && {
    printf '      combined mango+noctalia: %s KiB RSS\n' "$total_kb"
    ok "footprint recorded (compare with the Hyprland-stack baseline per success criterion 7)"
  }
}

# --- Main --------------------------------------------------------------------

STATIC=0
CONFIG_DIR="${HOME}/.config"
LOCK_LOOP=0
SUSPEND_PROBE=0
LAUNCH_APPS=0
FOOTPRINT=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --static)
      STATIC=1
      shift
      if [ "$#" -gt 0 ] && [ "${1#--}" = "$1" ]; then
        CONFIG_DIR="$1"
        shift
      fi
      ;;
    --lock-loop)
      LOCK_LOOP="$2"
      shift 2
      ;;
    --suspend-probe)
      SUSPEND_PROBE=1
      shift
      ;;
    --launch-apps)
      LAUNCH_APPS=1
      shift
      ;;
    --footprint)
      FOOTPRINT=1
      shift
      ;;
    *)
      echo "usage: $0 [--static [CONFIG_DIR]] [--lock-loop N] [--suspend-probe] [--launch-apps] [--footprint]" >&2
      exit 2
      ;;
  esac
done

printf 'MangoWM + Noctalia validation (%s)\n' "$(date -Is)"

if [ "$STATIC" = "1" ]; then
  static_checks "$CONFIG_DIR"
else
  if [ -z "${MANGO_INSTANCE_SIGNATURE:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "      Not inside a Wayland session; run this inside the Mango session"
    echo "      or use --static for offline config validation." >&2
    exit 2
  fi

  section "Session preflight"
  [ -n "${MANGO_INSTANCE_SIGNATURE:-}" ] && ok "MANGO_INSTANCE_SIGNATURE set (Mango session detected)"
  [ -z "${MANGO_INSTANCE_SIGNATURE:-}" ] && skip "MANGO_INSTANCE_SIGNATURE not set"

  mmsg_checks
  noctalia_ipc_checks
  core_apps_checks
  screenshot_clipboard_checks
  screen_share_probe

  [ "$LOCK_LOOP" -gt 0 ] && lock_probe "$LOCK_LOOP"
  [ "$SUSPEND_PROBE" = "1" ] && suspend_probe
  [ "$FOOTPRINT" = "1" ] && footprint_report
fi

printf '\n== Summary: %s passed, %s failed, %s skipped ==\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
