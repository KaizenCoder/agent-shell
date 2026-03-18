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

  # Clear previous result and set trap for cleanup on Ctrl+C
  rm -f /tmp/.agent_shell_stream_result
  trap 'rm -f /tmp/.agent_shell_stream_result; echo; return 1' INT

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
        # Append to result file (subshell workaround)
        printf '%s' "$text_chunk" >> /tmp/.agent_shell_stream_result
      fi
    fi
  done

  trap - INT  # Restore default SIGINT handler
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
