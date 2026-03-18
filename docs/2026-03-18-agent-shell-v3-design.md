---
title: Agent Shell v3 - Multi-modes, Streaming, Config YAML
date: 2026-03-18
status: validated
---

# Agent Shell v3 Design

## Context
agent_shell v2 is a working bash function (~360 lines in ~/.agent_shell.sh) that converts natural language to shell commands via Gemini API. Features: memory, feedback loop, confirmation, cache, pipes. Based on ShellGPT analysis (priorities 1-5 implemented), this design covers priorities 6-8: streaming, multi-modes, config YAML.

## Architecture: Modular Bash

```
~/.agent_shell/
  config.yml          # User config + profiles
  core.sh             # Entry point, arg parsing, dispatch
  mode_shell.sh       # Shell mode (v2 behavior, no streaming)
  mode_code.sh        # Code mode + streaming
  mode_chat.sh        # Chat mode + streaming
  lib_api.sh          # API calls (normal + streaming via streamGenerateContent)
  lib_config.sh       # YAML parser (python3 inline, no pyyaml dep), merge hierarchy
  lib_cache.sh        # MD5 cache + per-mode history
  lib_common.sh       # Colors, display, clipboard, shared utils
```

Bashrc reduces to: `source ~/.agent_shell/core.sh`

## Config YAML Hierarchy

`defaults (lib_config.sh) < config.yml < env vars (AGENT_SHELL_*) < CLI flags (--profile, --model)`

### config.yml structure

```yaml
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
  expert:
    model: gemini-2.5-flash
    temperature: 0.3
    max_tokens: 4096
  local:
    model: ollama/llama3
    endpoint: "http://localhost:11434/v1/chat/completions"
    temperature: 0.2
    max_tokens: 2048

prompts:
  shell: |
    [current v2 system prompt]
  code: |
    [code generation prompt]
  chat: |
    [conversational prompt]
```

## CLI Interface

```bash
agent_shell "demande"                    # Default: shell mode, rapide profile
agent_code "demande"                     # Alias for --mode code
agent_chat "demande"                     # Alias for --mode chat
agent_shell --profile expert "demande"   # Override profile
agent_shell --model gemini-2.5-flash "demande"  # Override model
agent_shell --yolo "demande"             # No confirmation
agent_shell --edit                       # Open config.yml in $EDITOR
agent_shell --config                     # Show active merged config
agent_shell --reset                      # Clear history + cache
agent_shell --help                       # Help
```

## Mode Behaviors

| Aspect | Shell | Code | Chat |
|---|---|---|---|
| Streaming | No | Yes | Yes |
| Execution | Yes (eval) | No | No |
| Confirmation | Yes (O/n) | Copy/Save | No |
| Cache | Yes (24h) | No | No |
| Feedback loop | Yes | No | No |
| History | Yes | Yes | Yes |
| Default profile | rapide | expert | expert |
| Pipes/stdin | Yes | Yes | Yes |

## Streaming Implementation

- Shell mode: current `generateContent` endpoint (full response)
- Code/Chat modes: `streamGenerateContent` endpoint, NDJSON parsing line by line
- Two functions in lib_api.sh: `_agent_shell_call_api()` and `_agent_shell_call_api_stream()`

## Clipboard (WSL-aware)

Detection order: `clip.exe` (WSL) > `wl-copy` (Wayland) > `xclip` (X11). Fallback: print message "copie non disponible".

## History

Per-mode files: `~/.agent_shell/history_shell`, `history_code`, `history_chat`. Format unchanged: `USER:...\nMODEL:...`. Only stores prompts and LLM responses, never command output.

## YAML Parser

Inline Python3 (~30 lines), no pyyaml dependency. Handles our simple flat+nested format. Outputs shell-evaluable `key=value` pairs.

## Migration from v2

- `~/.agent_shell.sh` replaced by `~/.agent_shell/core.sh`
- `~/.bashrc` source line updated
- Existing `~/.agent_shell_history` migrated to `~/.agent_shell/history_shell`
- Existing `~/.cache/agent_shell/` stays (compatible)
- `GEMINI_API_KEY` stays in bashrc or moves to config.yml (user choice)
