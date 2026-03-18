#!/bin/bash
# lib_config.sh — YAML parser and config merge
# Uses inline Python3 for parsing (no pyyaml needed — our YAML is simple)

AGENT_SHELL_DIR="${AGENT_SHELL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
AGENT_SHELL_CONFIG="$AGENT_SHELL_DIR/config.yml"

# --- Parse config.yml and set shell variables ---
_agent_shell_load_config() {
  [[ ! -f "$AGENT_SHELL_CONFIG" ]] && { _agent_shell_debug "No config.yml found, using defaults"; return 0; }

  eval "$(python3 - "$AGENT_SHELL_CONFIG" <<'PYEOF'
import sys, re, os

config_path = sys.argv[1]
with open(config_path) as f:
    content = f.read()

# Extract top-level simple key: value pairs
for match in re.finditer(r'^(\w+):\s*"?([^"\n"]+)"?\s*$', content, re.MULTILINE):
    key, val = match.group(1), match.group(2).strip().strip('"')
    if key in ('api_key', 'default_mode', 'default_profile', 'max_history', 'cache_ttl', 'yolo', 'debug'):
        # Expand env vars like ${GEMINI_API_KEY}
        val = re.sub(r'\$\{(\w+)\}', lambda m: os.environ.get(m.group(1), ''), val)
        shell_key = f"AGENT_SHELL_{key.upper()}"
        print(f'{shell_key}={val!r}')
PYEOF
  )"
  _agent_shell_debug "Config loaded from $AGENT_SHELL_CONFIG"
}

# --- Load a specific profile's settings ---
_agent_shell_load_profile() {
  local profile_name="${1:-$AGENT_SHELL_DEFAULT_PROFILE}"
  [[ ! -f "$AGENT_SHELL_CONFIG" ]] && return 1

  eval "$(python3 - "$AGENT_SHELL_CONFIG" "$profile_name" <<'PYEOF'
import sys, re

config_path, profile_name = sys.argv[1], sys.argv[2]
with open(config_path) as f:
    content = f.read()

# Find the profile block
pattern = rf'  {re.escape(profile_name)}:\n((?:    .+\n)*)'
match = re.search(pattern, content)
if not match:
    sys.exit(0)

block = match.group(1)
mapping = {'model': 'MODEL', 'temperature': 'TEMPERATURE', 'max_tokens': 'MAX_TOKENS',
           'endpoint': 'ENDPOINT', 'description': 'PROFILE_DESC'}

for line in block.strip().split('\n'):
    m = re.match(r'\s*(\w+):\s*"?([^"\n]+)"?', line)
    if m and m.group(1) in mapping:
        key = f"AGENT_SHELL_{mapping[m.group(1)]}"
        val = m.group(2).strip().strip('"')
        print(f'{key}={val!r}')

print(f'AGENT_SHELL_PROFILE={profile_name!r}')
PYEOF
  )"
  _agent_shell_debug "Profile '$profile_name' loaded: model=$AGENT_SHELL_MODEL"
}

# --- Get system prompt for a mode ---
_agent_shell_get_prompt() {
  local mode="${1:-shell}"
  python3 - "$AGENT_SHELL_CONFIG" "$mode" <<'PYEOF'
import sys, re

config_path, mode = sys.argv[1], sys.argv[2]
with open(config_path) as f:
    content = f.read()

# Find the prompt block for this mode (indented with |)
# Extract all lines of the prompt block (4-space indented, including empty lines)
pattern = rf'  {re.escape(mode)}:\s*\|\n'
match = re.search(pattern, content)
if match:
    start = match.end()
    lines = []
    for line in content[start:].split('\n'):
        # Block continues while lines are indented (4+ spaces) or empty
        if line.startswith('    ') or line.strip() == '':
            lines.append(line[4:] if line.startswith('    ') else '')
        else:
            break
    print('\n'.join(lines).strip())
PYEOF
}

# --- Apply env var overrides (AGENT_SHELL_* vars set before sourcing) ---
_agent_shell_apply_overrides() {
  # Env vars already set take precedence — persist them in current shell
  local var
  for var in MODEL TEMPERATURE MAX_TOKENS ENDPOINT PROFILE DEFAULT_MODE DEFAULT_PROFILE MAX_HISTORY CACHE_TTL YOLO DEBUG API_KEY; do
    local full="AGENT_SHELL_${var}"
    [[ -n "${!full}" ]] && export "$full"="${!full}"
  done
  _agent_shell_debug "Overrides applied: MODEL=$AGENT_SHELL_MODEL"
}

# --- Show active config ---
_agent_shell_show_config() {
  echo "Agent Shell v3 — Configuration active"
  echo "======================================"
  echo "Mode:        ${AGENT_SHELL_DEFAULT_MODE:-shell}"
  echo "Profil:      ${AGENT_SHELL_PROFILE:-${AGENT_SHELL_DEFAULT_PROFILE:-rapide}}"
  echo "Modele:      ${AGENT_SHELL_MODEL:-non defini}"
  echo "Temperature: ${AGENT_SHELL_TEMPERATURE:-0.1}"
  echo "Max tokens:  ${AGENT_SHELL_MAX_TOKENS:-1024}"
  echo "Endpoint:    ${AGENT_SHELL_ENDPOINT:-Gemini default}"
  echo "Historique:  ${AGENT_SHELL_MAX_HISTORY:-10} derniers echanges"
  echo "Cache TTL:   ${AGENT_SHELL_CACHE_TTL:-86400}s"
  echo "YOLO:        ${AGENT_SHELL_YOLO:-false}"
  echo "Debug:       ${AGENT_SHELL_DEBUG:-false}"
  echo "Config:      $AGENT_SHELL_CONFIG"
}
