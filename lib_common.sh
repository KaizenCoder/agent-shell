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
