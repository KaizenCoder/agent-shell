#!/bin/bash
# tests/test_cache.sh — Tests for cache get/set + TTL
set -uo pipefail

PASS=0; FAIL=0
assert_true() { if eval "$1"; then ((PASS++)); else ((FAIL++)); echo "FAIL: $2"; fi; }
assert_eq() { if [[ "$1" == "$2" ]]; then ((PASS++)); else ((FAIL++)); echo "FAIL: expected '$2', got '$1' ($3)"; fi; }

TMPDIR="$(mktemp -d)"
AGENT_SHELL_CACHE_DIR="$TMPDIR/cache"
AGENT_SHELL_DIR="$TMPDIR/dir"
mkdir -p "$AGENT_SHELL_CACHE_DIR" "$AGENT_SHELL_DIR"

source "$(dirname "$0")/../lib_cache.sh"

# Test: set/get returns value
_agent_shell_cache_set "key1" "value1"
got=$(_agent_shell_cache_get "key1" || true)
assert_eq "$got" "value1" "cache get should return stored value"

# Test: TTL expiry
AGENT_SHELL_CACHE_TTL=1
_agent_shell_cache_set "key2" "expiring"
sleep 2
if _agent_shell_cache_get "key2" >/dev/null 2>&1; then
  ((FAIL++)); echo "FAIL: cache entry should have expired";
else
  ((PASS++));
fi

echo "lib_cache (cache): $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
