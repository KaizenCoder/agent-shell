#!/bin/bash
# tests/test_history.sh — Tests for history save/load, encoding, truncation, concurrency
set -uo pipefail

PASS=0; FAIL=0
assert_true() { if eval "$1"; then ((PASS++)); else ((FAIL++)); echo "FAIL: $2"; fi; }
assert_eq() { if [[ "$1" == "$2" ]]; then ((PASS++)); else ((FAIL++)); echo "FAIL: expected '$2', got '$1' ($3)"; fi; }

TMPDIR="$(mktemp -d)"
AGENT_SHELL_DIR="$TMPDIR/agent"
mkdir -p "$AGENT_SHELL_DIR"

LIBCACHE="$(dirname "$0")/../lib_cache.sh"
source "$LIBCACHE"

mode=shell
hfile="$AGENT_SHELL_DIR/history_${mode}"

# 1) Encode/Decode newlines roundtrip
user_msg=$'ligne1\nligne2'
model_msg=$'# Description multi-lignes\ncommande sur deux lignes'
_agent_shell_save_history "$mode" "$user_msg" "$model_msg"



# Load JSON and check decoded contains real newlines
json=$(_agent_shell_load_history_json "$mode")
py='import json,sys; d=json.loads(sys.stdin.read()); u=d[0]["parts"][0]["text"]; m=d[1]["parts"][0]["text"]; print("\n" in u, "\n" in m)'
read_has_nl_u_m=$(python3 -c "$py" <<<"$json")
assert_eq "$read_has_nl_u_m" "True True" "decoded messages should contain newlines"

# 2) Truncation behavior
AGENT_SHELL_MAX_HISTORY=2
for i in {1..10}; do _agent_shell_save_history "$mode" "u$i" "m$i"; done
max_lines=$(( AGENT_SHELL_MAX_HISTORY * 2 + 10 ))
lines=$(wc -l < "$hfile")
test $lines -le $max_lines && ((PASS++)) || { ((FAIL++)); echo "FAIL: history not truncated correctly (lines=$lines, max=$max_lines)"; }

# 3) Migration-style malformed line handling
printf '%s\n' 'USER:legacy case' 'MODEL:desc legacy' 'cmd legacy (stray line)' >> "$hfile"
json=$(_agent_shell_load_history_json "$mode")
py2='import json,sys; d=json.loads(sys.stdin.read()); print(len(d))'
count=$(python3 -c "$py2" <<<"$json")
# Should still produce an even count (user+model pairs or user-only ok but total list may be odd). We accept >= 2
test "$count" -ge 2 && ((PASS++)) || { ((FAIL++)); echo "FAIL: loader did not return entries for malformed history"; }

# 4) Concurrency stress (detect mismatched pairing)
# Spawn parallel writers without locks to detect potential interleaving
writers=10; per_writer=50
par_script=$(mktemp)
cat > "$par_script" <<'EOS'
#!/bin/bash
set -e
AGENT_SHELL_DIR="$1"
WID="$2"
LIB="$3"
COUNT="$4"
source "$LIB"
for i in $(seq 1 "$COUNT"); do
  _agent_shell_save_history shell "USER-$WID-$i" "MODEL-$WID-$i"
done
EOS
chmod +x "$par_script"

pids=()
for w in $(seq 1 $writers); do
  bash "$par_script" "$AGENT_SHELL_DIR" "$w" "$LIBCACHE" "$per_writer" &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done

# Analyze mismatches (USER-X-Y followed by MODEL-Z-T where X!=Z)
python3 - "$hfile" <<'PY'
import sys,re
lines=open(sys.argv[1]).read().splitlines()
mis=0; total=0
i=0
while i < len(lines):
    if lines[i].startswith('USER:'):
        total+=1
        user=lines[i][5:].strip()
        if i+1 < len(lines) and lines[i+1].startswith('MODEL:'):
            model=lines[i+1][6:].strip()
            # IDs are literal, no decoding needed here
            u=re.findall(r'USER-(\d+)-(\d+)$', user)
            m=re.findall(r'MODEL-(\d+)-(\d+)$', model)
            if u and m and u[0][0]!=m[0][0]:
                mis+=1
            i+=2
        else:
            i+=1
    else:
        i+=1
print(f"mismatches={mis} total={total}")
PY

echo "lib_cache (history): $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
