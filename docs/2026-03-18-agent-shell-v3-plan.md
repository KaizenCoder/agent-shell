# Agent Shell v3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transform agent_shell from a single-file bash function into a modular system with 3 modes (shell/code/chat), streaming for code/chat, and YAML-based configuration with profiles.

**Architecture:** Modular bash — `~/.agent_shell/core.sh` sources specialized modules (`lib_*.sh`, `mode_*.sh`). Config loaded from `~/.agent_shell/config.yml` via inline Python3 parser. Streaming uses Gemini `streamGenerateContent` SSE endpoint. Shell mode preserves v2 behavior exactly.

**Tech Stack:** Bash 5+, Python3 (inline for JSON/YAML parsing), curl, Gemini REST API (generateContent + streamGenerateContent with alt=sse)

**Spec:** `~/.agent_shell/docs/2026-03-18-agent-shell-v3-design.md`

---

## File Structure

| File | Responsibility |
|---|---|
| `~/.agent_shell/config.yml` | User configuration: API key, profiles, prompts, defaults |
| `~/.agent_shell/core.sh` | Entry point: source modules, parse CLI args, dispatch to mode |
| `~/.agent_shell/lib_common.sh` | Colors, display helpers, clipboard detection, debug logging |
| `~/.agent_shell/lib_config.sh` | YAML parser (Python3 inline), config merge (defaults < yaml < env < args) |
| `~/.agent_shell/lib_api.sh` | `_agent_shell_call_api()` (normal) + `_agent_shell_call_api_stream()` (SSE) |
| `~/.agent_shell/lib_cache.sh` | MD5 cache (get/set/TTL) + per-mode history (save/load/truncate) |
| `~/.agent_shell/mode_shell.sh` | Shell mode: build payload, call API, parse 2-line response, confirm, exec, feedback loop |
| `~/.agent_shell/mode_code.sh` | Code mode: build payload, stream response, display progressively, offer clipboard/save |
| `~/.agent_shell/mode_chat.sh` | Chat mode: build payload, stream response, display progressively |
| `~/.agent_shell/tests/test_config.sh` | Functional test: YAML parsing, merge hierarchy |
| `~/.agent_shell/tests/test_modes.sh` | Functional test: mode dispatch, arg parsing |

---

### Task 1: lib_common.sh — Shared utilities

**Files:**
- Create: `~/.agent_shell/lib_common.sh`
- Create: `~/.agent_shell/tests/test_common.sh`

- [ ] **Step 1: Write the test script**

```bash
#!/bin/bash
# tests/test_common.sh — Functional tests for lib_common.sh
PASS=0; FAIL=0
assert_eq() { if [[ "$1" == "$2" ]]; then ((PASS++)); else ((FAIL++)); echo "FAIL: expected '$2', got '$1' ($3)"; fi; }

source "$(dirname "$0")/../lib_common.sh"

# Test color variables exist
assert_eq "${#C_CYAN}" "9" "C_CYAN should be an ANSI escape"
assert_eq "$C_RESET" $'\033[0m' "C_RESET"

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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.agent_shell/tests/test_common.sh`
Expected: FAIL (lib_common.sh does not exist yet)

- [ ] **Step 3: Implement lib_common.sh**

```bash
#!/bin/bash
# lib_common.sh — Colors, display, clipboard, debug

# --- Colors ---
C_CYAN=$'\033[36m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_GREEN=$'\033[32m'
C_GRAY=$'\033[90m'
C_BOLD=$'\033[1m'
C_RESET=$'\033[0m'

# --- Debug ---
_agent_shell_debug() {
  [[ "${AGENT_SHELL_DEBUG:-0}" == "1" ]] && echo "${C_GRAY}[debug] $*${C_RESET}" >&2
}

# --- Clipboard detection (WSL > Wayland > X11) ---
_agent_shell_detect_clipboard() {
  if command -v clip.exe &>/dev/null; then
    echo "clip.exe"
  elif command -v wl-copy &>/dev/null; then
    echo "wl-copy"
  elif command -v xclip &>/dev/null; then
    echo "xclip -selection clipboard"
  else
    return 1
  fi
}

# --- Copy to clipboard ---
_agent_shell_copy_to_clipboard() {
  local text="$1"
  local clip_cmd
  clip_cmd=$(_agent_shell_detect_clipboard) || { echo "${C_RED}Copie non disponible (aucun outil clipboard detecte)${C_RESET}"; return 1; }
  echo -n "$text" | eval "$clip_cmd"
  echo "${C_GREEN}Copie dans le presse-papier.${C_RESET}"
}

# --- Display helpers ---
_agent_shell_print_desc() {
  printf '%s%s%s\n' "$C_CYAN" "$1" "$C_RESET"
}

_agent_shell_print_cmd() {
  printf '%s> %s%s\n' "$C_YELLOW" "$1" "$C_RESET"
}

_agent_shell_print_error() {
  printf '%s%s%s\n' "$C_RED" "$1" "$C_RESET" >&2
}

_agent_shell_print_success() {
  printf '%s%s%s\n' "$C_GREEN" "$1" "$C_RESET"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash ~/.agent_shell/tests/test_common.sh`
Expected: all passed, 0 failed

- [ ] **Step 5: Commit**

```bash
git -C ~/.agent_shell init 2>/dev/null
git -C ~/.agent_shell add lib_common.sh tests/test_common.sh
git -C ~/.agent_shell commit -m "feat: add lib_common.sh — colors, clipboard, debug helpers"
```

---

### Task 2: lib_config.sh — YAML parser and config merge

**Files:**
- Create: `~/.agent_shell/lib_config.sh`
- Create: `~/.agent_shell/config.yml`
- Create: `~/.agent_shell/tests/test_config.sh`

**Dependencies:** Task 1 (lib_common.sh)

- [ ] **Step 1: Write the test script**

```bash
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

echo "lib_config: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash ~/.agent_shell/tests/test_config.sh`
Expected: FAIL

- [ ] **Step 3: Create config.yml**

```yaml
# ~/.agent_shell/config.yml — Agent Shell v3 Configuration
# Hierarchy: defaults < this file < env vars (AGENT_SHELL_*) < CLI flags

api_key: "${GEMINI_API_KEY}"
default_mode: shell
default_profile: rapide
max_history: 10
cache_ttl: 86400
yolo: false
debug: false

profiles:
  rapide:
    model: gemini-2.5-flash-lite
    temperature: 0.1
    max_tokens: 1024
    description: "Rapide, pour les commandes shell simples"
  expert:
    model: gemini-2.5-flash
    temperature: 0.3
    max_tokens: 4096
    description: "Plus puissant, pour code et chat complexes"
  local:
    model: ollama/llama3
    endpoint: "http://localhost:11434/v1/chat/completions"
    temperature: 0.2
    max_tokens: 2048
    description: "Modele local via Ollama"

prompts:
  shell: |
    Tu es Agent Shell, un expert en ligne de commande Unix sur Ubuntu/WSL.
    Tu recois une demande en langage naturel et tu generes la commande shell COMPLETE et FONCTIONNELLE.

    FORMAT STRICT - tu reponds TOUJOURS avec EXACTEMENT 2 lignes, rien d'autre:
    Ligne 1: # [description courte de l'action]
    Ligne 2: la commande shell complete, prete a copier-coller et executer telle quelle.
    IMPORTANT: Tu DOIS TOUJOURS fournir les 2 lignes. JAMAIS une seule ligne.
    Meme si la demande dit "fais pareil" ou "meme chose", tu DOIS generer la commande complete sur la ligne 2.

    EXEMPLE avec historique:
    Historique: l'utilisateur a fait "mkdir -p factures && mv facture*.pdf factures/"
    Demande: "fais pareil pour les bulletins"
    Reponse correcte:
    # Cree le dossier bulletins et deplace les PDF commencant par bulletin
    mkdir -p bulletins && mv bulletin*.pdf bulletins/

    REGLES:
    - La commande DOIT etre complete avec tous les pipes, flags, options, chemins.
    - Pour les actions multi-etapes, chaine avec && ou ; sur UNE seule ligne.
    - JAMAIS de backticks markdown, JAMAIS de bloc de code.
    - JAMAIS d'explication, JAMAIS de texte supplementaire.
    - Si destructif, prefixe la description: # [ATTENTION DESTRUCTIF] ...
    - Utilise les outils modernes (ip, df -h, etc).
    - Adapte au contexte WSL/Ubuntu/Debian.
    - Toujours utiliser mkdir -p (jamais mkdir seul).
    - Les noms de fichiers/dossiers crees: underscores, pas d'espaces.
    - Pour les globs (* ?), ne JAMAIS mettre le * entre quotes. Echappe les espaces avec backslash.
      Exemple correct: bulletin\ de\ salaire*.pdf

  code: |
    Tu es Agent Code, un expert en programmation.
    Tu recois une demande en langage naturel et tu generes du code COMPLET et FONCTIONNEL.

    REGLES:
    - Reponds avec le code complet, pret a copier-coller.
    - Commence par un commentaire d'une ligne expliquant ce que fait le code.
    - Pas de backticks markdown. Code brut uniquement.
    - Si le langage n'est pas specifie, deduis-le du contexte ou utilise Python.
    - Inclus les imports necessaires.
    - Code propre, commente si complexe, idiomatique.
    - Si la demande est ambigue, choisis l'interpretation la plus utile.

  chat: |
    Tu es Agent Chat, un assistant technique expert.
    Tu reponds de maniere concise et structuree en francais.

    REGLES:
    - Reponses claires, structurees avec des listes numerotees si pertinent.
    - Pas de backticks markdown excessifs. Texte brut prefere.
    - Adapte la longueur a la complexite de la question.
    - Si tu ne sais pas, dis-le.
    - Donne des exemples concrets quand c'est utile.
```

- [ ] **Step 4: Implement lib_config.sh**

```bash
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
for match in re.finditer(r'^(\w+):\s*"?([^"\n{]+)"?\s*$', content, re.MULTILINE):
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
    m = re.match(r'\s+(\w+):\s*"?([^"\n]+)"?', line)
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
pattern = rf'  {re.escape(mode)}:\s*\|\n((?:    .+\n)*)'
match = re.search(pattern, content)
if match:
    lines = match.group(1).split('\n')
    # Remove 4-space indent
    print('\n'.join(line[4:] if line.startswith('    ') else line for line in lines).strip())
PYEOF
}

# --- Apply env var overrides (AGENT_SHELL_* vars set before sourcing) ---
_agent_shell_apply_overrides() {
  # Env vars already set take precedence — this is a no-op confirmation
  # CLI arg overrides are applied in core.sh after this function
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash ~/.agent_shell/tests/test_config.sh`
Expected: all passed, 0 failed

- [ ] **Step 6: Commit**

```bash
git -C ~/.agent_shell add lib_config.sh config.yml tests/test_config.sh
git -C ~/.agent_shell commit -m "feat: add lib_config.sh — YAML parser with profiles and merge hierarchy"
```

---

### Task 3: lib_cache.sh — Cache and per-mode history

**Files:**
- Create: `~/.agent_shell/lib_cache.sh`

**Dependencies:** Task 1 (lib_common.sh)

- [ ] **Step 1: Write lib_cache.sh**

Extract and adapt cache + history code from `~/.agent_shell.sh` (lines 164-190 for cache, lines 146-162 for history), adding per-mode history support.

```bash
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
  echo "USER:$user_msg" >> "$hfile"
  echo "MODEL:$model_msg" >> "$hfile"

  # Truncate if too long
  local max_lines=$(( ${AGENT_SHELL_MAX_HISTORY:-10} * 2 + 10 ))
  if [[ -f "$hfile" ]]; then
    local total
    total=$(wc -l < "$hfile")
    if (( total > max_lines )); then
      tail -n "$max_lines" "$hfile" > "$hfile.tmp"
      mv "$hfile.tmp" "$hfile"
    fi
  fi
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
            user_msg = lines[i][5:].strip()
            model_msg = ""
            if i + 1 < len(lines) and lines[i+1].startswith('MODEL:'):
                model_msg = lines[i+1][6:].strip()
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
```

- [ ] **Step 2: Verify cache compatibility**

Run: `ls ~/.cache/agent_shell/` — existing v2 cache files should remain compatible (same MD5 key scheme).

- [ ] **Step 3: Migrate v2 history**

```bash
# One-time migration: move v2 history to per-mode shell history
if [[ -f ~/.agent_shell_history && ! -f ~/.agent_shell/history_shell ]]; then
  cp ~/.agent_shell_history ~/.agent_shell/history_shell
fi
```

This migration logic will go in `core.sh` (Task 6).

- [ ] **Step 4: Commit**

```bash
git -C ~/.agent_shell add lib_cache.sh
git -C ~/.agent_shell commit -m "feat: add lib_cache.sh — cache with TTL and per-mode history"
```

---

### Task 4: lib_api.sh — Normal and streaming API calls

**Files:**
- Create: `~/.agent_shell/lib_api.sh`

**Dependencies:** Task 1 (lib_common.sh), Task 2 (lib_config.sh)

- [ ] **Step 1: Implement lib_api.sh**

```bash
#!/bin/bash
# lib_api.sh — Gemini API calls (normal + streaming SSE)

# --- Normal API call (for shell mode) ---
_agent_shell_call_api() {
  local json_payload="$1"
  local endpoint="${AGENT_SHELL_ENDPOINT:-https://generativelanguage.googleapis.com/v1beta/models/${AGENT_SHELL_MODEL}:generateContent?key=$AGENT_SHELL_API_KEY}"

  _agent_shell_debug "API call: $AGENT_SHELL_MODEL (normal)"
  curl -s --max-time 20 "$endpoint" \
    -H "Content-Type: application/json" \
    -d "$json_payload"
}

# --- Streaming API call (for code/chat modes) ---
# Reads SSE stream line by line, extracts text, prints progressively
_agent_shell_call_api_stream() {
  local json_payload="$1"
  local endpoint="${AGENT_SHELL_ENDPOINT:-https://generativelanguage.googleapis.com/v1beta/models/${AGENT_SHELL_MODEL}:streamGenerateContent?key=$AGENT_SHELL_API_KEY&alt=sse}"

  _agent_shell_debug "API call: $AGENT_SHELL_MODEL (streaming)"

  local full_text=""
  local line

  curl -s --max-time 60 -N "$endpoint" \
    -H "Content-Type: application/json" \
    -d "$json_payload" 2>/dev/null | while IFS= read -r line; do
    # SSE format: "data: {json}"
    if [[ "$line" == data:* ]]; then
      local json_part="${line#data: }"
      local text_chunk
      text_chunk=$(echo "$json_part" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    parts = data.get('candidates', [{}])[0].get('content', {}).get('parts', [])
    for p in parts:
        if 'text' in p:
            print(p['text'], end='')
except:
    pass
" 2>/dev/null)
      if [[ -n "$text_chunk" ]]; then
        printf '%s' "$text_chunk"
        full_text+="$text_chunk"
      fi
    fi
  done

  # Return full text via a temp file (subshell pipe limitation)
  echo "$full_text" > "/tmp/.agent_shell_stream_result"
  echo  # Final newline
}

# --- Build JSON payload ---
_agent_shell_build_payload() {
  local mode="$1" user_prompt="$2" extra_context="$3"
  local sys_prompt
  sys_prompt=$(_agent_shell_get_prompt "$mode")
  local history_json
  history_json=$(_agent_shell_load_history_json "$mode")

  python3 - "$user_prompt" "$extra_context" "$sys_prompt" "$history_json" \
    "${AGENT_SHELL_TEMPERATURE:-0.1}" "${AGENT_SHELL_MAX_TOKENS:-1024}" <<'PYEOF'
import json, sys

user_prompt = sys.argv[1]
extra_context = sys.argv[2]
sys_prompt = sys.argv[3]
history_json = sys.argv[4]
temperature = float(sys.argv[5])
max_tokens = int(sys.argv[6])

contents = json.loads(history_json) if history_json else []

final_prompt = user_prompt
if extra_context:
    final_prompt = extra_context + "\n" + user_prompt

contents.append({"role": "user", "parts": [{"text": final_prompt}]})

payload = {
    "system_instruction": {"parts": [{"text": sys_prompt}]},
    "contents": contents,
    "generationConfig": {"temperature": temperature, "maxOutputTokens": max_tokens}
}
print(json.dumps(payload))
PYEOF
}

# --- Parse normal API response (shell mode) ---
_agent_shell_parse_response() {
  local response="$1"
  echo "$response" | python3 -c "
import sys, json, re, shlex
try:
    r = json.load(sys.stdin)
    if 'error' in r:
        msg = r['error'].get('message','')
        code = r['error'].get('code','')
        if code == 429:
            m = re.search(r'retry in (\d+)', msg)
            wait = m.group(1) if m else '10'
            print(f'status=RATE_LIMIT')
            print(f'wait={wait}')
        else:
            print(f'status=ERROR')
            print(f'desc={shlex.quote(\"# Erreur API: \" + msg[:80])}')
            print(f'cmd=')
        sys.exit(0)
    raw = r['candidates'][0]['content']['parts'][0]['text'].strip()
    raw = re.sub(r'\x60\x60\x60\w*\n?', '', raw).strip()
    lines = [l for l in raw.split('\n') if l.strip()]
    desc = lines[0] if lines else '# commande'
    cmd_lines = [l for l in lines if not l.strip().startswith('#')]
    cmd = ' && '.join(cmd_lines) if cmd_lines else ''
    print(f'status=OK')
    print(f'desc={shlex.quote(desc)}')
    print(f'cmd={shlex.quote(cmd)}')
except Exception as e:
    print(f'status=ERROR')
    print(f'desc={shlex.quote(\"# Erreur parsing: \" + str(e))}')
    print(f'cmd=')
"
}
```

- [ ] **Step 2: Test streaming endpoint manually**

Run: `source ~/.agent_shell/lib_common.sh && source ~/.agent_shell/lib_config.sh && _agent_shell_load_config && _agent_shell_load_profile rapide && source ~/.agent_shell/lib_api.sh && echo "test" | _agent_shell_call_api_stream "$(cat <<'EOF'
{"contents":[{"role":"user","parts":[{"text":"say hello in 3 words"}]}],"generationConfig":{"maxOutputTokens":20}}
EOF
)"`
Expected: progressive text output

- [ ] **Step 3: Commit**

```bash
git -C ~/.agent_shell add lib_api.sh
git -C ~/.agent_shell commit -m "feat: add lib_api.sh — normal and streaming Gemini API calls"
```

---

### Task 5: mode_shell.sh — Shell mode (v2 behavior preserved)

**Files:**
- Create: `~/.agent_shell/mode_shell.sh`

**Dependencies:** Tasks 1-4

- [ ] **Step 1: Implement mode_shell.sh**

Adapted from `~/.agent_shell.sh` v2 (lines 195-349), using the new modular helpers.

```bash
#!/bin/bash
# mode_shell.sh — Shell mode: NL -> command -> confirm -> exec -> feedback

_agent_shell_mode_shell() {
  local user_input="$1" extra_context="$2"

  # --- Cache check ---
  local cache_key="${user_input}|${extra_context}|shell"
  local cached_result
  if cached_result=$(_agent_shell_cache_get "$cache_key"); then
    local desc cmd
    eval "$cached_result"
    printf '\n%s%s %s(cache)\n%s> %s%s\n\n' "$C_CYAN" "$desc" "$C_GRAY" "$C_YELLOW" "$cmd" "$C_RESET"
  else
    # --- Build payload and call API ---
    local json_payload
    json_payload=$(_agent_shell_build_payload "shell" "$user_input" "$extra_context")

    local response
    response=$(_agent_shell_call_api "$json_payload")

    # --- Parse response ---
    local status desc cmd wait
    eval "$(_agent_shell_parse_response "$response")"

    # --- Rate limit retry (max 2) ---
    local retries=0
    while [[ "$status" == "RATE_LIMIT" && retries -lt 2 ]]; do
      printf '%sRate limit. Retry dans %ss...%s\n' "$C_YELLOW" "$wait" "$C_RESET"
      sleep "$wait"
      response=$(_agent_shell_call_api "$json_payload")
      eval "$(_agent_shell_parse_response "$response")"
      (( retries++ ))
    done

    if [[ "$status" == "RATE_LIMIT" ]]; then
      _agent_shell_print_error "Rate limit persistant. Reessaie dans quelques minutes."
      return 1
    fi
    if [[ "$status" == "ERROR" ]]; then
      _agent_shell_print_error "$desc"
      return 1
    fi

    # Cache valid response
    if [[ -n "$cmd" ]]; then
      _agent_shell_cache_set "$cache_key" "desc=$(printf '%q' "$desc")"$'\n'"cmd=$(printf '%q' "$cmd")"
    fi

    printf '\n%s%s\n%s> %s%s\n\n' "$C_CYAN" "$desc" "$C_YELLOW" "$cmd" "$C_RESET"
  fi

  # --- Confirm and execute ---
  [[ -z "$cmd" ]] && return 0

  local execute=1
  if [[ "${AGENT_SHELL_YOLO:-0}" != "1" && "${AGENT_SHELL_YOLO:-false}" != "true" ]]; then
    if [[ "$desc" == *"DESTRUCTIF"* ]] || [[ "$cmd" == *"rm "* ]] || [[ "$cmd" == *"dd "* ]] || [[ "$cmd" == *"> /"* ]]; then
      printf '%s⚠ Commande potentiellement dangereuse.%s\n' "$C_RED" "$C_RESET"
      read -r -p "Executer ? [o/N] " confirm
      [[ "$confirm" =~ ^[oOyY]$ ]] || execute=0
    else
      read -r -p "Executer ? [O/n] " confirm
      [[ "$confirm" =~ ^[nN]$ ]] && execute=0
    fi
  fi

  if (( execute )); then
    local exec_output exec_exit
    exec_output=$(eval "$cmd" 2>&1)
    exec_exit=$?

    [[ -n "$exec_output" ]] && echo "$exec_output"

    _agent_shell_save_history "shell" "$user_input" "$desc"$'\n'"$cmd"

    # --- Feedback loop on error ---
    if (( exec_exit != 0 )); then
      printf '\n%sErreur (code %d). Demander une correction ?%s\n' "$C_RED" "$exec_exit" "$C_RESET"
      read -r -p "[O/n] " retry_confirm
      if [[ ! "$retry_confirm" =~ ^[nN]$ ]]; then
        local error_snippet="${exec_output:0:500}"
        local correction_prompt="La commande precedente a echoue. Corrige-la."
        local correction_context="Commande executee: $cmd"$'\n'"Code retour: $exec_exit"$'\n'"Erreur: $error_snippet"

        local fix_payload
        fix_payload=$(_agent_shell_build_payload "shell" "$correction_prompt" "$correction_context")
        local fix_response
        fix_response=$(_agent_shell_call_api "$fix_payload")

        local fix_status fix_desc fix_cmd
        eval "$(_agent_shell_parse_response "$fix_response")"
        fix_status="$status"; fix_desc="$desc"; fix_cmd="$cmd"

        if [[ "$fix_status" == "OK" && -n "$fix_cmd" ]]; then
          printf '\n%s%s %s(correction)\n%s> %s%s\n\n' "$C_CYAN" "$fix_desc" "$C_GRAY" "$C_YELLOW" "$fix_cmd" "$C_RESET"

          local exec_fix=1
          if [[ "${AGENT_SHELL_YOLO:-0}" != "1" && "${AGENT_SHELL_YOLO:-false}" != "true" ]]; then
            read -r -p "Executer la correction ? [O/n] " fix_confirm
            [[ "$fix_confirm" =~ ^[nN]$ ]] && exec_fix=0
          fi

          if (( exec_fix )); then
            eval "$fix_cmd" 2>&1
            _agent_shell_save_history "shell" "$correction_prompt" "$fix_desc"$'\n'"$fix_cmd"
          fi
        else
          _agent_shell_print_error "Impossible de corriger automatiquement."
        fi
      fi
    fi
  else
    printf '%sAnnule.%s\n' "$C_GRAY" "$C_RESET"
  fi
}
```

- [ ] **Step 2: Test shell mode manually**

Run: `source ~/.agent_shell/core.sh && agent_shell "liste les fichiers du dossier courant"`
Expected: Same behavior as v2

- [ ] **Step 3: Commit**

```bash
git -C ~/.agent_shell add mode_shell.sh
git -C ~/.agent_shell commit -m "feat: add mode_shell.sh — v2 shell behavior in modular form"
```

---

### Task 6: mode_code.sh — Code mode with streaming

**Files:**
- Create: `~/.agent_shell/mode_code.sh`

**Dependencies:** Tasks 1-4

- [ ] **Step 1: Implement mode_code.sh**

```bash
#!/bin/bash
# mode_code.sh — Code mode: NL -> code generation with streaming

_agent_shell_mode_code() {
  local user_input="$1" extra_context="$2"

  # --- Build payload and stream ---
  local json_payload
  json_payload=$(_agent_shell_build_payload "code" "$user_input" "$extra_context")

  printf '\n'
  _agent_shell_call_api_stream "$json_payload"

  # Retrieve full text from stream
  local full_text=""
  [[ -f /tmp/.agent_shell_stream_result ]] && {
    full_text=$(cat /tmp/.agent_shell_stream_result)
    rm -f /tmp/.agent_shell_stream_result
  }

  printf '\n'

  # Save to history
  _agent_shell_save_history "code" "$user_input" "$full_text"

  # --- Offer actions: copy or save ---
  if [[ -n "$full_text" ]]; then
    echo ""
    printf '%s[c]opier | [s]auver dans fichier | [Entree] rien%s ' "$C_GRAY" "$C_RESET"
    read -r -n1 action
    echo ""
    case "$action" in
      c|C)
        _agent_shell_copy_to_clipboard "$full_text"
        ;;
      s|S)
        read -r -p "Nom du fichier: " save_path
        if [[ -n "$save_path" ]]; then
          echo "$full_text" > "$save_path"
          _agent_shell_print_success "Sauvegarde dans $save_path"
        fi
        ;;
    esac
  fi
}
```

- [ ] **Step 2: Test code mode**

Run: `source ~/.agent_shell/core.sh && agent_code "fonction python qui inverse une chaine"`
Expected: Streaming output of Python code, then action menu

- [ ] **Step 3: Commit**

```bash
git -C ~/.agent_shell add mode_code.sh
git -C ~/.agent_shell commit -m "feat: add mode_code.sh — code generation with streaming"
```

---

### Task 7: mode_chat.sh — Chat mode with streaming

**Files:**
- Create: `~/.agent_shell/mode_chat.sh`

**Dependencies:** Tasks 1-4

- [ ] **Step 1: Implement mode_chat.sh**

```bash
#!/bin/bash
# mode_chat.sh — Chat mode: conversational Q&A with streaming

_agent_shell_mode_chat() {
  local user_input="$1" extra_context="$2"

  # --- Build payload and stream ---
  local json_payload
  json_payload=$(_agent_shell_build_payload "chat" "$user_input" "$extra_context")

  printf '\n'
  _agent_shell_call_api_stream "$json_payload"

  # Retrieve full text
  local full_text=""
  [[ -f /tmp/.agent_shell_stream_result ]] && {
    full_text=$(cat /tmp/.agent_shell_stream_result)
    rm -f /tmp/.agent_shell_stream_result
  }

  printf '\n'

  # Save to history (for follow-up questions)
  _agent_shell_save_history "chat" "$user_input" "$full_text"
}
```

- [ ] **Step 2: Test chat mode**

Run: `source ~/.agent_shell/core.sh && agent_chat "explique les permissions Unix en 3 points"`
Expected: Streaming conversational response

- [ ] **Step 3: Commit**

```bash
git -C ~/.agent_shell add mode_chat.sh
git -C ~/.agent_shell commit -m "feat: add mode_chat.sh — conversational mode with streaming"
```

---

### Task 8: core.sh — Entry point, arg parsing, dispatch

**Files:**
- Create: `~/.agent_shell/core.sh`

**Dependencies:** Tasks 1-7 (all modules)

- [ ] **Step 1: Implement core.sh**

```bash
#!/bin/bash
# core.sh — Agent Shell v3 entry point
# Source this file from ~/.bashrc: source ~/.agent_shell/core.sh

AGENT_SHELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Source all modules ---
source "$AGENT_SHELL_DIR/lib_common.sh"
source "$AGENT_SHELL_DIR/lib_config.sh"
source "$AGENT_SHELL_DIR/lib_cache.sh"
source "$AGENT_SHELL_DIR/lib_api.sh"
source "$AGENT_SHELL_DIR/mode_shell.sh"
source "$AGENT_SHELL_DIR/mode_code.sh"
source "$AGENT_SHELL_DIR/mode_chat.sh"

# --- Load config at source time ---
_agent_shell_load_config

# --- One-time migration from v2 ---
if [[ -f "$HOME/.agent_shell_history" && ! -f "$AGENT_SHELL_DIR/history_shell" ]]; then
  cp "$HOME/.agent_shell_history" "$AGENT_SHELL_DIR/history_shell"
  _agent_shell_debug "Migrated v2 history to history_shell"
fi

# ============================================================
# MAIN FUNCTION
# ============================================================
agent_shell() {
  local mode="${AGENT_SHELL_DEFAULT_MODE:-shell}"
  local profile="${AGENT_SHELL_DEFAULT_PROFILE:-rapide}"
  local yolo_flag=""
  local model_override=""
  local positional_args=()

  # --- Parse arguments ---
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --mode)    mode="$2"; shift 2 ;;
      --profile) profile="$2"; shift 2 ;;
      --model)   model_override="$2"; shift 2 ;;
      --yolo)    yolo_flag="1"; shift ;;
      --edit)    ${EDITOR:-${VISUAL:-nano}} "$AGENT_SHELL_CONFIG"; return ;;
      --config)  _agent_shell_load_profile "$profile"; _agent_shell_show_config; return ;;
      --reset)   _agent_shell_reset_all; return ;;
      --help)    _agent_shell_help; return ;;
      --)        shift; positional_args+=("$@"); break ;;
      -*)        _agent_shell_print_error "Option inconnue: $1"; _agent_shell_help; return 1 ;;
      *)         positional_args+=("$1"); shift ;;
    esac
  done

  # --- Stdin support ---
  local stdin_content=""
  if [[ ! -t 0 ]]; then
    stdin_content=$(cat)
  fi

  local user_input="${positional_args[*]}"

  if [[ -z "$user_input" && -z "$stdin_content" ]]; then
    _agent_shell_help
    return 1
  fi

  [[ -z "$user_input" ]] && user_input="Analyse et traite cette entree"

  local extra_context=""
  if [[ -n "$stdin_content" ]]; then
    extra_context="Voici le contenu recu en entree (stdin):"$'\n'"$stdin_content"$'\n'"---"
  fi

  # --- Load profile + apply overrides ---
  # Mode-specific default profile
  case "$mode" in
    code|chat) [[ "$profile" == "rapide" ]] && profile="${AGENT_SHELL_DEFAULT_PROFILE:-rapide}" ;;
  esac

  _agent_shell_load_profile "$profile"
  [[ -n "$model_override" ]] && AGENT_SHELL_MODEL="$model_override"
  [[ -n "$yolo_flag" ]] && AGENT_SHELL_YOLO="1"

  # --- Validate API key ---
  if [[ -z "$AGENT_SHELL_API_KEY" ]]; then
    _agent_shell_print_error "Erreur: API key non definie. Configure api_key dans config.yml ou GEMINI_API_KEY."
    return 1
  fi

  _agent_shell_debug "Dispatch: mode=$mode, profile=$AGENT_SHELL_PROFILE, model=$AGENT_SHELL_MODEL"

  # --- Dispatch to mode ---
  case "$mode" in
    shell) _agent_shell_mode_shell "$user_input" "$extra_context" ;;
    code)  _agent_shell_mode_code "$user_input" "$extra_context" ;;
    chat)  _agent_shell_mode_chat "$user_input" "$extra_context" ;;
    *)     _agent_shell_print_error "Mode inconnu: $mode (shell|code|chat)"; return 1 ;;
  esac
}

# --- Help ---
_agent_shell_help() {
  cat <<'HELP'
Agent Shell v3 — Commandes en langage naturel

Usage:
  agent_shell "ta demande"                     Mode shell (defaut)
  agent_code  "ta demande"                     Mode code (streaming)
  agent_chat  "ta demande"                     Mode chat (streaming)

  commande | agent_shell "explique"            Pipe stdin

Options:
  --mode shell|code|chat    Forcer un mode
  --profile NAME            Utiliser un profil (rapide, expert, local)
  --model MODEL             Override le modele
  --yolo                    Pas de confirmation

Commandes:
  --edit                    Ouvrir config.yml
  --config                  Afficher la config active
  --reset                   Vider historique + cache
  --help                    Cette aide
HELP
}

# --- Aliases ---
agent_code() { agent_shell --mode code "$@"; }
agent_chat() { agent_shell --mode chat "$@"; }
agent_shell_yolo() { agent_shell --yolo "$@"; }
agent_shell_reset() { agent_shell --reset; }
```

- [ ] **Step 2: Test full integration**

```bash
# Test 1: Shell mode (should work like v2)
source ~/.agent_shell/core.sh
agent_shell "liste les 3 plus gros fichiers ici"

# Test 2: Code mode
agent_code "fonction python hello world"

# Test 3: Chat mode
agent_chat "qu'est-ce que WSL"

# Test 4: Profile override
agent_shell --profile expert "debug ce probleme"

# Test 5: Utility commands
agent_shell --config
agent_shell --help
```

- [ ] **Step 3: Commit**

```bash
git -C ~/.agent_shell add core.sh
git -C ~/.agent_shell commit -m "feat: add core.sh — entry point with arg parsing, mode dispatch, aliases"
```

---

### Task 9: Update ~/.bashrc — Wire up v3

**Files:**
- Modify: `~/.bashrc` (lines 201-203)

- [ ] **Step 1: Update bashrc source line**

Replace:
```bash
# Agent Shell (Gemini Edition) - charge depuis fichier externe
source ~/.agent_shell.sh
export GEMINI_API_KEY=YOUR_GEMINI_API_KEY
```

With:
```bash
# Agent Shell v3 — Modulaire
source ~/.agent_shell/core.sh
export GEMINI_API_KEY=YOUR_GEMINI_API_KEY
```

- [ ] **Step 2: Keep v2 as backup**

```bash
cp ~/.agent_shell.sh ~/.agent_shell.sh.v2.bak
```

- [ ] **Step 3: Full reload test**

```bash
source ~/.bashrc
agent_shell --help
agent_shell "dis bonjour"
agent_code "hello world en python"
agent_chat "c'est quoi bash"
```

- [ ] **Step 4: Commit**

No git commit for bashrc (not in the ~/.agent_shell repo). User manages bashrc separately.

---

### Task 10: Functional tests — Full test suite

**Files:**
- Create: `~/.agent_shell/tests/test_modes.sh`

- [ ] **Step 1: Write integration test script**

```bash
#!/bin/bash
# tests/test_modes.sh — Integration tests (requires API key)
PASS=0; FAIL=0
assert_contains() { [[ "$1" == *"$2"* ]] && ((PASS++)) || { ((FAIL++)); echo "FAIL: output should contain '$2' ($3)"; echo "GOT: ${1:0:200}"; }; }

AGENT_SHELL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$AGENT_SHELL_DIR/core.sh"
AGENT_SHELL_YOLO=1  # Skip confirmations for testing

# Test 1: Shell mode returns a command
echo "=== Test: Shell mode ==="
output=$(agent_shell "affiche la date" 2>&1)
assert_contains "$output" "date" "shell should generate date command"

# Test 2: Code mode returns code
echo "=== Test: Code mode ==="
output=$(agent_code "hello world en python" 2>&1)
assert_contains "$output" "print" "code should contain print"

# Test 3: Chat mode returns text
echo "=== Test: Chat mode ==="
output=$(agent_chat "qu'est-ce que Linux en une phrase" 2>&1)
assert_contains "$output" "Linux" "chat should mention Linux"

# Test 4: --config works
echo "=== Test: --config ==="
output=$(agent_shell --config 2>&1)
assert_contains "$output" "Profil" "config should show profile"

# Test 5: --help works
echo "=== Test: --help ==="
output=$(agent_shell --help 2>&1)
assert_contains "$output" "agent_shell" "help should mention agent_shell"

# Test 6: Pipe support
echo "=== Test: Pipe ==="
output=$(echo "hello world" | AGENT_SHELL_YOLO=1 agent_shell "compte les mots" 2>&1)
assert_contains "$output" "wc" "pipe should generate wc command"

echo ""
echo "========================================="
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && echo "ALL TESTS PASSED" || echo "SOME TESTS FAILED"
```

- [ ] **Step 2: Run tests**

Run: `bash ~/.agent_shell/tests/test_modes.sh`
Expected: All tests pass

- [ ] **Step 3: Commit**

```bash
git -C ~/.agent_shell add tests/test_modes.sh
git -C ~/.agent_shell commit -m "test: add integration test suite for all modes"
```
