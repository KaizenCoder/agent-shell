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
