#!/bin/bash
# tests/test_common.sh — Functional tests for lib_common.sh
PASS=0; FAIL=0
assert_eq() { if [[ "$1" == "$2" ]]; then ((PASS++)); else ((FAIL++)); echo "FAIL: expected '$2', got '$1' ($3)"; fi; }

source "$(dirname "$0")/../lib_common.sh"

# Test color variables exist
assert_eq "$C_RESET" $'\033[0m' "C_RESET"
assert_eq "$C_CYAN" $'\033[36m' "C_CYAN"
assert_eq "$C_RED" $'\033[31m' "C_RED"

# Test clipboard detection (WSL has clip.exe)
clip_cmd=$(_agent_shell_detect_clipboard)
assert_eq "$?" "0" "clipboard detection should succeed on WSL"

# Test debug logging (disabled)
AGENT_SHELL_DEBUG=0
output=$(_agent_shell_debug "test message" 2>&1)
assert_eq "$output" "" "debug off = no output"

# Test debug logging (enabled)
AGENT_SHELL_DEBUG=1
output=$(_agent_shell_debug "test message" 2>&1)
[[ "$output" == *"test message"* ]] && ((PASS++)) || { ((FAIL++)); echo "FAIL: debug on should output message"; }

echo "lib_common: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
