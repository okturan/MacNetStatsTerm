#!/bin/bash

calculate_rate() {
  local PREV=$1
  local NEXT=$2

  local RATE=$(echo "scale=2; ($NEXT - $PREV) / 1024" | bc)
  if (( $(echo "$RATE > 1024" | bc -l) )); then
    RATE=$(echo "scale=2; $RATE / 1024" | bc)
    printf "%.2f MB/s" "$RATE"
  else
    printf "%.2f KB/s" "$RATE"
  fi
}

get_active_interface() {
  route get 8.8.8.8 | grep interface | awk '{print $2}' || echo "en0"
}

print_network_stats() {
  INTERFACE=$(get_active_interface)
  RXPREV=$(netstat -I "$INTERFACE" -b | awk 'FNR == 2 {print $7}')
  TXPREV=$(netstat -I "$INTERFACE" -b | awk 'FNR == 2 {print $10}')
  sleep 1
  RXNEXT=$(netstat -I "$INTERFACE" -b | awk 'FNR == 2 {print $7}')
  TXNEXT=$(netstat -I "$INTERFACE" -b | awk 'FNR == 2 {print $10}')

  DOWNLOAD_RATE=$(calculate_rate "$RXPREV" "$RXNEXT")
  UPLOAD_RATE=$(calculate_rate "$TXPREV" "$TXNEXT")

  # Set text formatting and colors using tput
  BOLD=$(tput bold)
  GREEN=$(tput setaf 2)
  BLUE=$(tput setaf 4)
  RED=$(tput setaf 1)
  NORMAL=$(tput sgr0)

  # Print the header with formatted text and colors
  echo "${BOLD}${GREEN}NETWORK MONITOR${NORMAL}"
  echo "${BOLD}${BLUE}============================${NORMAL}"
  echo "Interface: ${BOLD}${GREEN}$INTERFACE${NORMAL}"
  echo "Download: ${BOLD}${BLUE}$DOWNLOAD_RATE${NORMAL} | Upload: ${BOLD}${RED}$UPLOAD_RATE${NORMAL}"
}

# Disable terminal cursor blinking
tput civis

# Continuous monitoring loop
while true; do
  # Move cursor to beginning of the output and clear line
  tput cup 0 0

  # Print network statistics
  print_network_stats

  # Wait for a second before the next update
  sleep 1
done

# Enable terminal cursor blinking
tput cnorm
