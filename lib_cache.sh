#!/bin/bash
# lib_cache.sh — MD5 cache and per-mode history

AGENT_SHELL_DIR="${AGENT_SHELL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
AGENT_SHELL_CACHE_DIR="$HOME/.cache/agent_shell"

# --- Cache ---
_agent_shell_cache_key() {
  echo -n "$1" | md5sum | cut -d' ' -f1
}

_agent_shell_cache_get() {
  local key
  key=$(_agent_shell_cache_key "$1")
  local cache_file="$AGENT_SHELL_CACHE_DIR/$key"
  if [[ -f "$cache_file" ]]; then
    local age
    age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
    if (( age < ${AGENT_SHELL_CACHE_TTL:-86400} )); then
      cat "$cache_file"
      return 0
    fi
  fi
  return 1
}

_agent_shell_cache_set() {
  local key
  key=$(_agent_shell_cache_key "$1")
  mkdir -p "$AGENT_SHELL_CACHE_DIR"
  echo "$2" > "$AGENT_SHELL_CACHE_DIR/$key"
}

# --- Per-mode history ---
_agent_shell_history_file() {
  local mode="${1:-shell}"
  echo "$AGENT_SHELL_DIR/history_${mode}"
}

_agent_shell_save_history() {
  local mode="$1" user_msg="$2" model_msg="$3"
  local hfile
  hfile=$(_agent_shell_history_file "$mode")
  # Encode newlines as \\n to keep one line per entry
  # Use a file lock to avoid interleaving under concurrent writers
  local lockfile="${hfile}.lock"
  (
    flock -x 200
    printf '%s\n%s\n' \
      "USER:${user_msg//$'\n'/\\n}" \
      "MODEL:${model_msg//$'\n'/\\n}" \
      >> "$hfile"

    # Truncate if too long (also under lock)
    local max_lines=$(( ${AGENT_SHELL_MAX_HISTORY:-10} * 2 + 10 ))
    if [[ -f "$hfile" ]]; then
      local total
      total=$(wc -l < "$hfile")
      if (( total > max_lines )); then
        local tmp="${hfile}.tmp.$$"
        tail -n "$max_lines" "$hfile" > "$tmp" && mv "$tmp" "$hfile"
      fi
    fi
  ) 200>>"$lockfile"
}

_agent_shell_load_history_json() {
  local mode="$1"
  local hfile
  hfile=$(_agent_shell_history_file "$mode")
  local max_history="${AGENT_SHELL_MAX_HISTORY:-10}"

  python3 - "$hfile" "$max_history" <<'PYEOF'
import json, sys, os

hfile = sys.argv[1]
max_h = int(sys.argv[2])

contents = []
if os.path.exists(hfile):
    with open(hfile) as f:
        lines = f.readlines()
    pairs = []
    i = 0
    while i < len(lines):
        if lines[i].startswith('USER:'):
            user_msg = lines[i][5:].strip().replace('\\n', '\n')
            model_msg = ""
            if i + 1 < len(lines) and lines[i+1].startswith('MODEL:'):
                model_msg = lines[i+1][6:].strip().replace('\\n', '\n')
                i += 2
            else:
                i += 1
            pairs.append((user_msg, model_msg))
        else:
            i += 1
    for u, m in pairs[-max_h:]:
        contents.append({"role": "user", "parts": [{"text": u}]})
        if m:
            contents.append({"role": "model", "parts": [{"text": m}]})

print(json.dumps(contents))
PYEOF
}

_agent_shell_reset_all() {
  rm -f "$AGENT_SHELL_DIR"/history_*
  rm -rf "$AGENT_SHELL_CACHE_DIR"
  echo "${C_GREEN:-}Historique et cache effaces.${C_RESET:-}"
}
