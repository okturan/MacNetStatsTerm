#!/bin/bash
set -euo pipefail  # Exit on error, undefined variables, and pipe failures

# Constants
readonly KB_TO_MB_THRESHOLD=1024
readonly REFRESH_INTERVAL=1

# Global variables for colors (initialized once)
BOLD=""
GREEN=""
BLUE=""
RED=""
NORMAL=""

# Cleanup function to restore terminal state
cleanup() {
  tput rmcup  # Exit alternate screen buffer
  tput cnorm  # Show cursor
  tput sgr0   # Reset text attributes
  exit 0
}

# Set up signal traps to ensure cleanup on exit
trap cleanup EXIT INT TERM

# Initialize color codes
init_colors() {
  if [ -t 1 ]; then  # Check if stdout is a terminal
    BOLD=$(tput bold)
    GREEN=$(tput setaf 2)
    BLUE=$(tput setaf 4)
    RED=$(tput setaf 1)
    NORMAL=$(tput sgr0)
  fi
}

# Calculate transfer rate with automatic unit scaling
calculate_rate() {
  local prev=$1
  local next=$2

  local rate_kb
  rate_kb=$(echo "scale=2; ($next - $prev) / 1024" | bc)

  if (( $(echo "$rate_kb > $KB_TO_MB_THRESHOLD" | bc -l) )); then
    local rate_mb
    rate_mb=$(echo "scale=2; $rate_kb / 1024" | bc)
    printf "%.2f MB/s" "$rate_mb"
  else
    printf "%.2f KB/s" "$rate_kb"
  fi
}

# Detect the active network interface
get_active_interface() {
  local interface
  interface=$(route get 8.8.8.8 2>/dev/null | grep interface | awk '{print $2}')

  if [ -z "$interface" ]; then
    echo "en0"  # Fallback to default
    return 1
  fi

  echo "$interface"
}

# Get network statistics for a given interface
get_network_bytes() {
  local interface=$1
  netstat -I "$interface" -b 2>/dev/null | awk 'FNR == 2 {print $7, $10}'
}

# Collect network statistics and calculate rates
collect_stats() {
  local interface=$1
  local rx_prev tx_prev rx_next tx_next

  read -r rx_prev tx_prev < <(get_network_bytes "$interface")
  sleep "$REFRESH_INTERVAL"
  read -r rx_next tx_next < <(get_network_bytes "$interface")

  local download_rate upload_rate
  download_rate=$(calculate_rate "$rx_prev" "$rx_next")
  upload_rate=$(calculate_rate "$tx_prev" "$tx_next")

  echo "$download_rate" "$upload_rate"
}

# Render the network monitor display
render_display() {
  local interface=$1
  local download_rate=$2
  local upload_rate=$3

  echo "${BOLD}${GREEN}NETWORK MONITOR${NORMAL}"
  echo "${BOLD}${BLUE}============================${NORMAL}"
  echo "Interface: ${BOLD}${GREEN}$interface${NORMAL}"
  echo "Download: ${BOLD}${BLUE}$download_rate${NORMAL} | Upload: ${BOLD}${RED}$upload_rate${NORMAL}"
}

# Main function
main() {
  # Initialize colors once
  init_colors

  # Detect interface once at startup
  local interface
  interface=$(get_active_interface)

  # Enter alternate screen buffer and hide cursor
  tput smcup
  clear
  tput civis

  # Continuous monitoring loop
  while true; do
    # Move cursor to beginning (overwrite existing content)
    tput cup 0 0

    # Collect statistics and render display
    local download_rate upload_rate
    read -r download_rate upload_rate < <(collect_stats "$interface")
    render_display "$interface" "$download_rate" "$upload_rate"
  done
}

# Run the main function
main
