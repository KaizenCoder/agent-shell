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
