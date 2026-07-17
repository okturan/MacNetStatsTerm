#!/bin/bash

# Constants
readonly KB_TO_MB_THRESHOLD=1024
readonly REFRESH_INTERVAL=1

# Terminal state. These remain empty when the file is sourced for tests.
BOLD=""
GREEN=""
BLUE=""
RED=""
NORMAL=""
SCREEN_ACTIVE=0

print_error() {
  printf 'MacNetStatsTerm: %s\n' "$*" >&2
}

is_non_negative_integer() {
  case "${1:-}" in
    '' | *[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

# Accept command names as arguments so dependency failures can be tested
# without changing PATH or relying on a particular machine image.
check_dependencies() {
  local command_name
  local missing=""

  for command_name in "$@"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing="${missing}${missing:+ }${command_name}"
    fi
  done

  if [ -n "$missing" ]; then
    print_error "missing required command(s): $missing"
    return 1
  fi
}

require_dependencies() {
  check_dependencies route netstat awk tput sleep
}

# Calculate a rate from two cumulative byte counters. Counter resets are
# clamped to zero rather than rendered as negative throughput.
calculate_rate() {
  local previous=${1:-}
  local current=${2:-}
  local interval=${3:-}

  if ! is_non_negative_integer "$previous" ||
    ! is_non_negative_integer "$current" ||
    ! is_non_negative_integer "$interval" ||
    [ "$interval" -eq 0 ]; then
    print_error "rate counters and interval must be non-negative integers; interval must be greater than zero"
    return 1
  fi

  awk \
    -v previous="$previous" \
    -v current="$current" \
    -v interval="$interval" \
    -v threshold="$KB_TO_MB_THRESHOLD" \
    'BEGIN {
      delta = current - previous
      if (delta < 0) {
        delta = 0
      }
      rate_kb = delta / 1024 / interval
      if (rate_kb >= threshold) {
        printf "%.2f MB/s", rate_kb / 1024
      } else {
        printf "%.2f KB/s", rate_kb
      }
    }'
}

calculate_transfer_rates() {
  local rx_previous=${1:-}
  local tx_previous=${2:-}
  local rx_current=${3:-}
  local tx_current=${4:-}
  local interval=${5:-}
  local download_rate
  local upload_rate

  download_rate=$(calculate_rate "$rx_previous" "$rx_current" "$interval") || return 1
  upload_rate=$(calculate_rate "$tx_previous" "$tx_current" "$interval") || return 1
  printf '%s|%s\n' "$download_rate" "$upload_rate"
}

# Detect the interface used by the local default route. An explicit override
# is useful on Macs with VPN, bridge, or multiple active interfaces.
get_active_interface() {
  local interface=""
  local fallback=${NETMON_FALLBACK_INTERFACE:-en0}

  if [ -n "${NETMON_INTERFACE:-}" ]; then
    printf '%s\n' "$NETMON_INTERFACE"
    return 0
  fi

  if ! interface=$(route -n get default 2>/dev/null | awk '$1 == "interface:" { print $2; exit }'); then
    interface=""
  fi

  if [ -z "$interface" ]; then
    print_error "could not detect the default-route interface; using $fallback (override with NETMON_INTERFACE)"
    printf '%s\n' "$fallback"
    return 0
  fi

  printf '%s\n' "$interface"
}

get_network_bytes() {
  local interface=${1:-}
  local bytes
  local rx
  local tx
  local extra

  if [ -z "$interface" ]; then
    print_error "an interface name is required"
    return 1
  fi

  if ! bytes=$(netstat -I "$interface" -b 2>/dev/null | awk '
    FNR == 2 { print $7, $10; found = 1; exit }
    END { if (!found) exit 1 }
  '); then
    print_error "could not read byte counters for interface $interface"
    return 1
  fi

  IFS=' ' read -r rx tx extra <<< "$bytes"
  if ! is_non_negative_integer "$rx" ||
    ! is_non_negative_integer "$tx" ||
    [ -n "${extra:-}" ]; then
    print_error "netstat returned invalid byte counters for interface $interface"
    return 1
  fi

  printf '%s %s\n' "$rx" "$tx"
}

collect_stats() {
  local interface=${1:-}
  local previous
  local current
  local rx_previous
  local tx_previous
  local rx_current
  local tx_current

  previous=$(get_network_bytes "$interface") || return 1
  IFS=' ' read -r rx_previous tx_previous <<< "$previous"

  sleep "$REFRESH_INTERVAL"

  current=$(get_network_bytes "$interface") || return 1
  IFS=' ' read -r rx_current tx_current <<< "$current"

  calculate_transfer_rates \
    "$rx_previous" \
    "$tx_previous" \
    "$rx_current" \
    "$tx_current" \
    "$REFRESH_INTERVAL"
}

cleanup() {
  if [ "${SCREEN_ACTIVE:-0}" -eq 1 ]; then
    tput cnorm 2>/dev/null || true
    tput sgr0 2>/dev/null || true
    tput rmcup 2>/dev/null || true
    SCREEN_ACTIVE=0
  fi
}

init_colors() {
  if [ -t 1 ]; then
    BOLD=$(tput bold 2>/dev/null || printf '')
    GREEN=$(tput setaf 2 2>/dev/null || printf '')
    BLUE=$(tput setaf 4 2>/dev/null || printf '')
    RED=$(tput setaf 1 2>/dev/null || printf '')
    NORMAL=$(tput sgr0 2>/dev/null || printf '')
  fi
}

render_display() {
  local interface=${1:-}
  local download_rate=${2:-}
  local upload_rate=${3:-}

  printf '%s%sNETWORK MONITOR%s\n' "$BOLD" "$GREEN" "$NORMAL"
  printf '%s%s============================%s\n' "$BOLD" "$BLUE" "$NORMAL"
  printf 'Interface: %s%s%s\n' "$BOLD" "$GREEN" "$interface$NORMAL"
  printf 'Download: %s%s%s | Upload: %s%s%s\n' \
    "$BOLD" "$BLUE" "$download_rate$NORMAL" \
    "$BOLD" "$RED" "$upload_rate$NORMAL"
}

main() {
  local interface
  local stats
  local download_rate
  local upload_rate

  if [ ! -t 1 ]; then
    print_error "an interactive terminal is required"
    return 1
  fi

  require_dependencies
  init_colors
  interface=$(get_active_interface)

  if ! tput smcup; then
    print_error "the current terminal does not support an alternate screen buffer"
    return 1
  fi

  SCREEN_ACTIVE=1
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  tput clear
  tput civis

  while true; do
    tput cup 0 0
    stats=$(collect_stats "$interface")
    IFS='|' read -r download_rate upload_rate <<< "$stats"
    render_display "$interface" "$download_rate" "$upload_rate"
  done
}

# Sourcing this file exposes the functions without installing traps or
# starting the monitor. Direct execution retains strict-mode CLI behavior.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  main "$@"
fi
