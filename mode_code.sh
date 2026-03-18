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
