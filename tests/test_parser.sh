#!/bin/bash
# tests/test_parser.sh — Contract tests for _agent_shell_parse_response
set -uo pipefail

PASS=0; FAIL=0
assert_eq() { if [[ "$1" == "$2" ]]; then ((PASS++)); else ((FAIL++)); echo "FAIL: expected '$2', got '$1' ($3)"; fi; }

AGENT_SHELL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$AGENT_SHELL_DIR/lib_api.sh"

run_case() {
  local fixture="$1"; shift
  local exp_status="$1"; shift
  local exp_desc="$1"; shift
  local exp_cmd="$1"; shift

  local resp
  resp=$(cat "$fixture")
  local status desc cmd wait
  eval "$(_agent_shell_parse_response "$resp")"
  assert_eq "$status" "$exp_status" "$fixture: status"
  [[ -n "$exp_desc" ]] && assert_eq "$desc" "$exp_desc" "$fixture: desc"
  [[ -n "$exp_cmd"  || "$exp_cmd" == "" ]] && assert_eq "$cmd" "$exp_cmd" "$fixture: cmd"
}

fixtures_dir="$AGENT_SHELL_DIR/tests/fixtures"

# 1) OK — 2 lignes (desc+cmd)
run_case "$fixtures_dir/ok.json" "OK" "# Affiche la date du jour" "date"

# 2) One line — commande seule
run_case "$fixtures_dir/one_line.json" "OK" "date" "date"

# 3) Description seule — commande vide
run_case "$fixtures_dir/desc_only.json" "OK" "# Juste une description sans commande" ""

# 4) Rate limit 429 — statut et wait
resp=$(cat "$fixtures_dir/error_429.json")
eval "$(_agent_shell_parse_response "$resp")"
assert_eq "$status" "RATE_LIMIT" "error_429: status"
assert_eq "$wait" "5" "error_429: wait"

# 5) Backticks d'ouverture — nettoyés
run_case "$fixtures_dir/backticks.json" "OK" "ls -l" "ls -l"

echo "parser: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
