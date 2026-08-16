#!/usr/bin/env bash
#
# mango-probe-lib.sh — bounded client-window polling shared by
# scripts/validate-mango-session.sh (--launch-apps) and its regression
# tests (scripts/test-mango-probe.sh).
#
# Implements the probe fix from the scout diagnosis
# (data/nixos-mango-core-app-probe-scout/report.md): the core-app probe
# used a single `sleep 3` snapshot of `mmsg get all-clients` and then
# killed the app, so cold-starting Firefox (XWayland) and Thunar windows
# could never map before the probe decided — two false negatives that were
# proven probe races, not desktop defects. The polling here keeps the fast
# path (first snapshot after 3 s) and then waits up to 30 s, returning a
# verdict only after the timeout or a confirmed match. The probed app is
# never terminated while the probe is still polling.
#
# This file defines functions only; it must be sourced. It relies on the
# consumer providing the `have` helper (command -v wrapper) and, for
# probe_client_window, the ok/bad/skip verdict printers.

# stop_probe_process <pid> — terminate a launched probe app and reap it.
# Only called AFTER wait_for_client has returned (timeout or confirmed
# match); the probe never kills an app while it is still polling.
stop_probe_process() {
  local pid="$1"

  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
}

# client_matches <marker> <mode> — read an `mmsg get all-clients` payload
# on stdin; exit 0 if a client matches. Mode window: the marker is a
# substring of the client title or appid (plain grep, no jq needed).
# Mode xwayland: additionally requires .is_xwayland == true via the real
# Mango schema (jq required; the caller skips the probe when jq is
# missing, mirroring the original probe's guard).
client_matches() {
  local marker="$1"
  local mode="$2"

  if [ "$mode" = "xwayland" ]; then
    have "jq" || return 1
    jq -e --arg marker "$marker" '
      any(.clients[]?;
        (((.title // "") | contains($marker)) or
          ((.appid // "") | contains($marker))) and
        .is_xwayland == true)
    ' >/dev/null 2>&1
    return $?
  fi

  grep -Fq -- "$marker"
  return $?
}

# client_list_diagnostics <json> — compact per-client summary of an
# all-clients snapshot (count plus title/appid/is_xwayland per client),
# printed to stdout. Falls back to the raw payload when jq is missing.
client_list_diagnostics() {
  local clients="$1"

  if have "jq"; then
    jq -r '
      "clients: \(.clients | length)",
      (.clients[]? |
        "  title=\"\(.title // "")\" appid=\"\(.appid // "")\" is_xwayland=\(.is_xwayland // false)")
    ' <<<"$clients" 2>/dev/null || printf '%s\n' "$clients"
  else
    printf '%s\n' "$clients"
  fi
}

# wait_for_client <marker> [--xwayland] [--timeout N] [--first-delay N]
#
# Poll `mmsg get all-clients` (from PATH) every second until a client
# matching <marker> appears, or the timeout expires. The first snapshot
# is taken after --first-delay seconds (default 3) so apps that map
# quickly still pass in a single check; polling then continues every
# second until --timeout (default 30).
#
# Never kills or stops anything; process cleanup is the caller's decision
# after this returns. On timeout, prints the verdict and the last client
# snapshot as diagnostics to stderr.
#
# Exit: 0 = matched; 1 = timeout; 2 = usage error.
wait_for_client() {
  local marker="${1:-}"
  local mode="window"
  local timeout=30
  local first_delay=3
  local opt=""
  local waited=0
  local clients=""
  local last_clients=""

  if [ -z "$marker" ]; then
    echo "wait_for_client: missing marker argument" >&2
    return 2
  fi
  shift

  while [ "$#" -gt 0 ]; do
    opt="$1"
    case "$opt" in
      --xwayland)
        mode="xwayland"
        shift
        ;;
      --timeout)
        if [ "$#" -lt 2 ]; then
          echo "wait_for_client: --timeout needs a value" >&2
          return 2
        fi
        timeout="$2"
        shift 2
        ;;
      --first-delay)
        if [ "$#" -lt 2 ]; then
          echo "wait_for_client: --first-delay needs a value" >&2
          return 2
        fi
        first_delay="$2"
        shift 2
        ;;
      *)
        echo "wait_for_client: unknown option: $opt" >&2
        return 2
        ;;
    esac
  done

  case "$timeout" in
    ''|*[!0-9]*)
      echo "wait_for_client: --timeout must be a non-negative integer: $timeout" >&2
      return 2
      ;;
  esac
  case "$first_delay" in
    ''|*[!0-9]*)
      echo "wait_for_client: --first-delay must be a non-negative integer: $first_delay" >&2
      return 2
      ;;
  esac

  if [ "$first_delay" -gt 0 ]; then
    sleep "$first_delay"
    waited="$first_delay"
  fi

  while :; do
    if ! clients="$(mmsg get all-clients 2>&1)"; then
      # Transient mmsg failure (compositor busy): keep polling; the
      # failure text becomes the last snapshot if nothing ever matches.
      last_clients="$clients"
    elif client_matches "$marker" "$mode" <<<"$clients"; then
      return 0
    else
      last_clients="$clients"
    fi

    if [ "$waited" -ge "$timeout" ]; then
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  echo "      no client matching '$marker' appeared within ${timeout}s (mode: $mode); last snapshot:" >&2
  client_list_diagnostics "$last_clients" >&2
  return 1
}

# print_app_stderr <label> <stderr_log> — print the tail of the probed
# app's captured stderr on timeout, so the run records why the app never
# mapped. No-op when no log was captured or it is empty.
print_app_stderr() {
  local label="$1"
  local stderr_log="$2"

  if [ -n "$stderr_log" ] && [ -s "$stderr_log" ]; then
    echo "      captured stderr from the launched $label:" >&2
    sed 's/^/      /' "$stderr_log" | tail -n 20 >&2
  fi
}

# probe_client_window <label> <marker> <pid> [cleanup] [mode] [stderr_log]
#
# Poll for the window of a launched app (see wait_for_client), print the
# PASS/FAIL verdict, and only then decide process cleanup:
#   cleanup=stop (default) — SIGTERM the app after the verdict;
#   cleanup=keep — leave the app running for the caller to stop.
# mode=window (default) matches the marker in title/appid; mode=xwayland
# requires an XWayland client (the real is_xwayland == true predicate;
# when jq is unavailable the probe is SKIPped and the app cleaned up,
# mirroring the original probe's guard). stderr_log, when given and
# non-empty, is printed on timeout so the run records why the app never
# mapped.
probe_client_window() {
  local label="$1"
  local marker="$2"
  local pid="$3"
  local cleanup="${4:-stop}"
  local mode="${5:-window}"
  local stderr_log="${6:-}"

  if [ "$mode" = "xwayland" ] && ! have "jq"; then
    skip "launched $label: jq is required for XWayland verification"
  elif [ "$mode" = "xwayland" ]; then
    if wait_for_client "$marker" --xwayland; then
      ok "launched $label is an XWayland client in mmsg get all-clients"
    else
      bad "launched $label is not reported as an XWayland client"
      print_app_stderr "$label" "$stderr_log"
    fi
  elif wait_for_client "$marker"; then
    ok "launched $label appears in mmsg get all-clients"
  else
    bad "launched $label not visible via mmsg get all-clients"
    print_app_stderr "$label" "$stderr_log"
  fi

  if [ "$cleanup" != "keep" ]; then
    stop_probe_process "$pid"
  fi
}
