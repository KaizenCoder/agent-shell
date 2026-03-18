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
