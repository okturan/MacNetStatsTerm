#!/bin/bash

set -u

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck source=netmon.sh
. "$ROOT_DIR/netmon.sh"

TESTS_RUN=0
TESTS_FAILED=0

fail() {
  printf '  FAIL: %s\n' "$*" >&2
  return 1
}

assert_equal() {
  local expected=$1
  local actual=$2
  local context=${3:-values differ}

  if [ "$expected" != "$actual" ]; then
    fail "$context (expected '$expected', got '$actual')"
  fi
}

assert_contains() {
  local haystack=$1
  local needle=$2
  local context=${3:-text not found}

  case "$haystack" in
    *"$needle"*) return 0 ;;
    *) fail "$context (missing '$needle' in '$haystack')" ;;
  esac
}

run_test() {
  local name=$1
  local test_function=$2
  TESTS_RUN=$((TESTS_RUN + 1))

  if "$test_function"; then
    printf 'ok %d - %s\n' "$TESTS_RUN" "$name"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf 'not ok %d - %s\n' "$TESTS_RUN" "$name"
  fi
}

test_rate_formats_kilobytes() {
  local actual
  actual=$(calculate_rate 0 2048 2)
  assert_equal "1.00 KB/s" "$actual" "two-second KB/s rate"
}

test_rate_scales_at_one_megabyte() {
  local actual
  actual=$(calculate_rate 0 1048576 1)
  assert_equal "1.00 MB/s" "$actual" "MB/s threshold"
}

test_transfer_pair_uses_independent_deltas() {
  local actual
  actual=$(calculate_transfer_rates 1000 2000 3048 2099152 2)
  assert_equal "1.00 KB/s|1.00 MB/s" "$actual" "download/upload pair"
}

test_counter_reset_is_clamped() {
  local actual
  actual=$(calculate_rate 4096 1024 1)
  assert_equal "0.00 KB/s" "$actual" "counter reset"
}

test_invalid_rate_input_fails() {
  local output
  local status
  output=$(calculate_rate invalid 1024 1 2>&1)
  status=$?

  assert_equal "1" "$status" "invalid input status" || return 1
  assert_contains "$output" "must be non-negative integers" "invalid input error"
}

test_detects_default_route_interface() {
  local actual

  # ShellCheck cannot see that get_active_interface resolves this test double.
  # shellcheck disable=SC2329
  route() {
    printf '   interface: en7\n'
  }

  actual=$(get_active_interface 2>/dev/null)
  unset -f route
  assert_equal "en7" "$actual" "detected interface"
}

test_route_failure_returns_successful_fallback() {
  local actual
  local status

  # ShellCheck cannot see that get_active_interface resolves this test double.
  # shellcheck disable=SC2329
  route() {
    return 1
  }

  actual=$(get_active_interface 2>/dev/null)
  status=$?
  unset -f route

  assert_equal "0" "$status" "fallback status" || return 1
  assert_equal "en0" "$actual" "fallback interface"
}

test_explicit_interface_bypasses_detection() {
  local actual
  actual=$(NETMON_INTERFACE=utun9 get_active_interface 2>/dev/null)
  assert_equal "utun9" "$actual" "explicit interface"
}

test_dependency_check_accepts_present_commands() {
  check_dependencies bash awk
}

test_dependency_check_reports_missing_commands() {
  local output
  local status
  output=$(check_dependencies __macnet_missing_one__ __macnet_missing_two__ 2>&1)
  status=$?

  assert_equal "1" "$status" "missing dependency status" || return 1
  assert_contains "$output" "__macnet_missing_one__ __macnet_missing_two__" "missing dependency list"
}

test_direct_execution_rejects_noninteractive_output() {
  local output
  local status
  output=$(bash "$ROOT_DIR/netmon.sh" 2>&1)
  status=$?

  assert_equal "1" "$status" "non-interactive status" || return 1
  assert_contains "$output" "interactive terminal is required" "non-interactive error"
}

test_version_is_available_without_a_terminal() {
  local actual
  actual=$(bash "$ROOT_DIR/netmon.sh" --version)
  assert_equal "MacNetStatsTerm 1.0.0" "$actual" "version output"
}

test_help_is_available_without_a_terminal() {
  local output
  output=$(bash "$ROOT_DIR/netmon.sh" --help)
  assert_contains "$output" "Usage: macnetstats" "help usage" || return 1
  assert_contains "$output" "NETMON_INTERFACE" "help environment"
}

test_unknown_option_fails_before_terminal_check() {
  local output
  local status
  output=$(bash "$ROOT_DIR/netmon.sh" --unknown 2>&1)
  status=$?

  assert_equal "2" "$status" "unknown option status" || return 1
  assert_contains "$output" "unknown option: --unknown" "unknown option error"
}

test_cleanup_restores_terminal_state() {
  local expected="cnorm sgr0 rmcup"
  TPUT_CALLS=""
  SCREEN_ACTIVE=1

  # ShellCheck cannot see that cleanup resolves this test double.
  # shellcheck disable=SC2329
  tput() {
    TPUT_CALLS="${TPUT_CALLS}${TPUT_CALLS:+ }$1"
  }

  cleanup
  unset -f tput

  assert_equal "$expected" "$TPUT_CALLS" "terminal cleanup order" || return 1
  assert_equal "0" "$SCREEN_ACTIVE" "terminal cleanup state"
}

printf '1..15\n'
run_test "formats KB/s using the sample interval" test_rate_formats_kilobytes
run_test "scales 1024 KB/s to MB/s" test_rate_scales_at_one_megabyte
run_test "calculates independent receive/transmit deltas" test_transfer_pair_uses_independent_deltas
run_test "clamps a reset cumulative counter" test_counter_reset_is_clamped
run_test "rejects invalid rate input" test_invalid_rate_input_fails
run_test "parses the default-route interface" test_detects_default_route_interface
run_test "returns a successful en0 fallback" test_route_failure_returns_successful_fallback
run_test "honors an explicit interface override" test_explicit_interface_bypasses_detection
run_test "accepts available dependencies" test_dependency_check_accepts_present_commands
run_test "reports all missing dependencies" test_dependency_check_reports_missing_commands
run_test "rejects direct non-interactive execution" test_direct_execution_rejects_noninteractive_output
run_test "prints the version without requiring a terminal" test_version_is_available_without_a_terminal
run_test "prints help without requiring a terminal" test_help_is_available_without_a_terminal
run_test "rejects an unknown option before terminal setup" test_unknown_option_fails_before_terminal_check
run_test "restores terminal state on cleanup" test_cleanup_restores_terminal_state

if [ "$TESTS_FAILED" -ne 0 ]; then
  printf '%d of %d tests failed\n' "$TESTS_FAILED" "$TESTS_RUN" >&2
  exit 1
fi

printf 'All %d tests passed\n' "$TESTS_RUN"
