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
#   --launch-apps     launch kitty/firefox/mpv/thunar/zathura and verify windows
#                     appear via mmsg
#   --footprint       print RSS of the experiment and fallback process sets
#   --footprint-only  print only the process footprint (for a stable baseline)
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

mango_session_detected() {
  if [ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]; then
    return 0
  fi

  case ":${XDG_CURRENT_DESKTOP:-}:" in
    *:mango:*) return 0 ;;
    *) return 1 ;;
  esac
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

noctalia_lock_state() {
  local status

  status="$(noctalia msg status 2>&1)" || {
    printf '%s\n' "$status" >&2
    return 1
  }
  jq -er 'if (.locked | type) == "boolean" then (.locked | tostring) else error("Noctalia status has no boolean locked field") end' <<<"$status"
}

check_noctalia_lock_state() {
  local expected="$1"
  local state

  if ! state="$(noctalia_lock_state 2>&1)"; then
    bad "Noctalia lock state query failed (expected $expected): $state"
    return 1
  fi
  if [ "$state" != "$expected" ]; then
    bad "Noctalia lock state is $state, expected $expected"
    return 1
  fi
  return 0
}

lock_probe() { # count
  local count="$1"
  local i

  section "Lock/unlock probe (Noctalia #3848, $count cycles)"

  require_tool "noctalia" "noctalia" || return
  require_tool "jq lock-state parser" "jq" || return

  echo "      The lock screen needs your password each round."
  for i in $(seq 1 "$count"); do
    printf '      cycle %s/%s: locking...\n' "$i" "$count"
    if ! noctalia msg session lock >/dev/null 2>&1; then
      bad "Noctalia lock command failed at cycle $i"
      return
    fi
    sleep 1
    if ! check_noctalia_lock_state true; then
      return
    fi
    echo "      locked; unlock it now, then press Enter"
    if ! read -r _; then
      bad "unlock confirmation input failed at cycle $i"
      return
    fi
    sleep 1
    if ! check_noctalia_lock_state false; then
      return
    fi
    echo "      cycle $i ok"
  done
  ok "lock/unlock x$count without hangs"
}

suspend_probe() {
  section "Suspend/resume probe (Mango #1017)"

  require_tool "noctalia" "noctalia" || return
  require_tool "systemctl" "systemctl" || return
  require_tool "jq lock-state parser" "jq" || return

  echo "      Locking, then suspending for ~20s; wake up and unlock manually."
  if ! noctalia msg session lock >/dev/null 2>&1; then
    bad "Noctalia lock command failed before suspend"
    return
  fi
  sleep 1
  if ! check_noctalia_lock_state true; then
    return
  fi

  if ! systemctl suspend >/dev/null 2>&1; then
    bad "systemctl suspend failed"
    return
  fi
  echo "      Resumed. Unlock the screen, then press Enter"
  if ! read -r _; then
    bad "unlock confirmation input failed after resume"
    return
  fi
  sleep 1
  if ! check_noctalia_lock_state false; then
    return
  fi

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

stop_probe_process() {
  local pid="$1"

  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
}

probe_client_window() {
  local label="$1"
  local marker="$2"
  local pid="$3"
  local clients

  sleep 3
  clients="$(mmsg get all-clients 2>&1)"
  if printf '%s\n' "$clients" | grep -Fq -- "$marker"; then
    ok "launched $label appears in mmsg get all-clients"
  else
    bad "launched $label not visible via mmsg get all-clients"
  fi

  stop_probe_process "$pid"
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

    local probe_dir marker pid thunar_dir pdf stream length
    local offset1 offset2 offset3 offset4 offset5 offset6 xref_offset

    if ! probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/mango-app-probe.XXXXXX")"; then
      bad "could not create the app probe workspace"
      return
    fi

    if have "kitty"; then
      marker="mango-kitty-probe-$$"
      kitty --class "$marker" >/dev/null 2>&1 &
      pid=$!
      probe_client_window "kitty" "$marker" "$pid"
    else
      skip "launch probe: kitty not found"
    fi

    if have "firefox"; then
      marker="mango-firefox-probe-$$"
      printf '<!doctype html><title>%s</title><p>Mango Firefox probe</p>\n' \
        "$marker" > "$probe_dir/probe.html"
      firefox \
        --new-instance \
        --no-remote \
        --profile "$probe_dir/firefox-profile" \
        --new-window "file://$probe_dir/probe.html" \
        >/dev/null 2>&1 &
      pid=$!
      probe_client_window "Firefox" "$marker" "$pid"
    else
      skip "launch probe: Firefox not found"
    fi

    if have "mpv"; then
      marker="mango-mpv-probe-$$"
      mpv \
        --no-config \
        --force-window=yes \
        --idle=yes \
        --title="$marker" \
        >/dev/null 2>&1 &
      pid=$!
      probe_client_window "mpv" "$marker" "$pid"
    else
      skip "launch probe: mpv not found"
    fi

    if have "thunar"; then
      marker="mango-thunar-probe-$$"
      thunar_dir="$probe_dir/$marker"
      mkdir -p "$thunar_dir"
      thunar --new-window "$thunar_dir" >/dev/null 2>&1 &
      pid=$!
      probe_client_window "Thunar" "$marker" "$pid"
    else
      skip "launch probe: Thunar not found"
    fi

    if have "zathura"; then
      marker="mango-zathura-probe-$$"
      pdf="$probe_dir/$marker.pdf"
      stream="BT /F1 18 Tf 20 100 Td (${marker}) Tj ET"
      length="${#stream}"

      printf '%%PDF-1.4\n' > "$pdf"
      offset1="$(wc -c < "$pdf")"
      printf '1 0 obj\n<< /Type /Catalog /Pages 2 0 R /Info 5 0 R >>\nendobj\n' >> "$pdf"
      offset2="$(wc -c < "$pdf")"
      printf '2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n' >> "$pdf"
      offset3="$(wc -c < "$pdf")"
      printf '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Contents 4 0 R /Resources << /Font << /F1 6 0 R >> >> >>\nendobj\n' >> "$pdf"
      offset4="$(wc -c < "$pdf")"
      printf '4 0 obj\n<< /Length %s >>\nstream\n%s\nendstream\nendobj\n' \
        "$length" "$stream" >> "$pdf"
      offset5="$(wc -c < "$pdf")"
      printf '5 0 obj\n<< /Title (%s) >>\nendobj\n' "$marker" >> "$pdf"
      offset6="$(wc -c < "$pdf")"
      printf '6 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n' >> "$pdf"
      xref_offset="$(wc -c < "$pdf")"
      printf 'xref\n0 7\n0000000000 65535 f \n%010d 00000 n \n%010d 00000 n \n%010d 00000 n \n%010d 00000 n \n%010d 00000 n \n%010d 00000 n \ntrailer\n<< /Size 7 /Root 1 0 R /Info 5 0 R >>\nstartxref\n%s\n%%%%EOF\n' \
        "$offset1" "$offset2" "$offset3" "$offset4" "$offset5" "$offset6" "$xref_offset" >> "$pdf"
      zathura "$pdf" >/dev/null 2>&1 &
      pid=$!
      probe_client_window "Zathura" "$marker" "$pid"
    else
      skip "launch probe: Zathura not found"
    fi

    rm -rf "$probe_dir"
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

process_rss() {
  local name="$1"
  local pid rss_kb total_kb=0 found=0

  for pid in $(pgrep -x "$name" 2>/dev/null); do
    rss_kb="$(awk '/VmRSS/ {print $2}' "/proc/$pid/status" 2>/dev/null)"
    case "$rss_kb" in
      ''|*[!0-9]*) continue ;;
    esac
    printf '      %s (pid %s): %s KiB RSS\n' "$name" "$pid" "$rss_kb"
    total_kb=$((total_kb + rss_kb))
    found=1
  done

  if [ "$found" = "0" ]; then
    skip "no running process named $name"
  fi

  PROCESS_TOTAL="$total_kb"
}

footprint_report() {
  section "Memory footprint"

  local name mango_total=0 noctalia_total=0 baseline_total=0

  for name in mango noctalia; do
    process_rss "$name"
    if [ "$name" = "mango" ]; then
      mango_total="$PROCESS_TOTAL"
    else
      noctalia_total="$PROCESS_TOTAL"
    fi
  done

  for name in waybar swaync fuzzel hyprlock hypridle hyprpaper; do
    process_rss "$name"
    baseline_total=$((baseline_total + PROCESS_TOTAL))
  done

  if [ "$mango_total" -gt 0 ] || [ "$noctalia_total" -gt 0 ]; then
    printf '      combined mango+noctalia: %s KiB RSS\n' "$((mango_total + noctalia_total))"
    ok "experiment footprint recorded"
  else
    skip "experiment footprint has no running Mango or Noctalia process"
  fi

  if [ "$noctalia_total" -gt 0 ] && [ "$baseline_total" -gt 0 ]; then
    printf '      Noctalia total: %s KiB RSS\n' "$noctalia_total"
    printf '      Hyprland-stack baseline: %s KiB RSS\n' "$baseline_total"
    ok "Noctalia-to-fallback footprint comparison recorded"
  else
    skip "footprint comparison needs Noctalia and the fallback process set"
  fi
}

# --- Main --------------------------------------------------------------------

STATIC=0
CONFIG_DIR="${HOME}/.config"
LOCK_LOOP=0
SUSPEND_PROBE=0
LAUNCH_APPS=0
FOOTPRINT=0
FOOTPRINT_ONLY=0

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
    --footprint-only)
      FOOTPRINT_ONLY=1
      shift
      ;;
    *)
      echo "usage: $0 [--static [CONFIG_DIR]] [--lock-loop N] [--suspend-probe] [--launch-apps] [--footprint] [--footprint-only]" >&2
      exit 2
      ;;
  esac
done

printf 'MangoWM + Noctalia validation (%s)\n' "$(date -Is)"

if [ "$STATIC" = "1" ]; then
  static_checks "$CONFIG_DIR"
elif [ "$FOOTPRINT_ONLY" = "1" ]; then
  footprint_report
else
  if ! mango_session_detected; then
    echo "      Mango session not detected; run this inside the Mango session" >&2
    echo "      or use --static/--footprint-only for offline checks." >&2
    exit 2
  fi

  section "Session preflight"
  if [ -n "${MANGO_INSTANCE_SIGNATURE:-}" ]; then
    ok "MANGO_INSTANCE_SIGNATURE set (Mango session detected)"
  else
    ok "XDG_CURRENT_DESKTOP includes mango (Mango session detected)"
  fi

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
