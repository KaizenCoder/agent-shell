#!/bin/bash
# tests/test_config.sh — Functional tests for lib_config.sh
PASS=0; FAIL=0
assert_eq() { if [[ "$1" == "$2" ]]; then ((PASS++)); else ((FAIL++)); echo "FAIL: expected '$2', got '$1' ($3)"; fi; }

AGENT_SHELL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$AGENT_SHELL_DIR/lib_common.sh"
source "$AGENT_SHELL_DIR/lib_config.sh"

# Test 1: Parse config.yml — default values
_agent_shell_load_config
assert_eq "$AGENT_SHELL_DEFAULT_MODE" "shell" "default_mode"
assert_eq "$AGENT_SHELL_DEFAULT_PROFILE" "rapide" "default_profile"
assert_eq "$AGENT_SHELL_MAX_HISTORY" "10" "max_history"
assert_eq "$AGENT_SHELL_CACHE_TTL" "86400" "cache_ttl"

# Test 2: Profile loading
_agent_shell_load_profile "rapide"
assert_eq "$AGENT_SHELL_MODEL" "gemini-2.5-flash-lite" "rapide model"
assert_eq "$AGENT_SHELL_TEMPERATURE" "0.1" "rapide temperature"

_agent_shell_load_profile "expert"
assert_eq "$AGENT_SHELL_MODEL" "gemini-2.5-flash" "expert model"
assert_eq "$AGENT_SHELL_TEMPERATURE" "0.3" "expert temperature"

# Test 3: Env var override
AGENT_SHELL_MODEL="override-model" _agent_shell_apply_overrides
assert_eq "$AGENT_SHELL_MODEL" "override-model" "env override"

# Test 4: Prompt loading
prompt=$(_agent_shell_get_prompt "shell")
[[ "$prompt" == *"Agent Shell"* ]] && ((PASS++)) || { ((FAIL++)); echo "FAIL: shell prompt should contain 'Agent Shell'"; }

prompt=$(_agent_shell_get_prompt "code")
[[ "$prompt" == *"Agent Code"* ]] && ((PASS++)) || { ((FAIL++)); echo "FAIL: code prompt should contain 'Agent Code'"; }

prompt=$(_agent_shell_get_prompt "chat")
[[ "$prompt" == *"Agent Chat"* ]] && ((PASS++)) || { ((FAIL++)); echo "FAIL: chat prompt should contain 'Agent Chat'"; }

echo "lib_config: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
