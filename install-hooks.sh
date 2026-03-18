#!/bin/bash
# install-hooks.sh — Installe les git hooks depuis hooks/ vers .git/hooks/
# Usage : ./install-hooks.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_SRC="$SCRIPT_DIR/hooks"
HOOKS_DST="$SCRIPT_DIR/.git/hooks"

if [[ ! -d "$HOOKS_SRC" ]]; then
  echo "Erreur: dossier hooks/ introuvable dans $SCRIPT_DIR"
  exit 1
fi

if [[ ! -d "$HOOKS_DST" ]]; then
  echo "Erreur: pas de repo git (.git/hooks/ introuvable)"
  exit 1
fi

installed=0
for hook in "$HOOKS_SRC"/*; do
  [[ -f "$hook" ]] || continue
  name=$(basename "$hook")
  cp "$hook" "$HOOKS_DST/$name"
  chmod +x "$HOOKS_DST/$name"
  echo "  Installe: $name"
  installed=$((installed + 1))
done

if [[ "$installed" -eq 0 ]]; then
  echo "Aucun hook a installer."
else
  echo "  $installed hook(s) installe(s)."
fi
