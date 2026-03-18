Mémoire projet — Agent Shell v3 (2026-03-18)

Contexte
- Architecture v3 modulaire (~/.agent_shell): core.sh, lib_*.sh, mode_*.sh, config.yml, docs/, tests/.
- 3 modes (shell, code, chat) avec historique par mode et streaming SSE OK.

Correctifs clés (session actuelle)
- Historique multi-lignes: encodage « \n » à la sauvegarde, décodage au chargement.
- Concurrence: verrouillage flock exclusif + écriture atomique + troncature sous le même verrou.

Détails techniques
- lib_cache.sh: _agent_shell_save_history() encode \n, utilise flock -x (FD 200), printf '%s\n%s\n' pour écrire USER/MODEL en une fois, puis tail | mv pour tronquer sous verrou.
- _agent_shell_load_history_json(): remplace « \\n » par vrais sauts de ligne.
- Historique: 1 entrée par ligne (format JSONL-like), sûreté en lecture même avec lignes orphelines migrées.

Tests ajoutés
- tests/test_cache.sh: TTL et set/get du cache (2 pass).
- tests/test_history.sh: encodage/décodage, troncature, robustesse migration, stress concurrent (3 pass).
- Stress test ad hoc: 20 writers x 200 paires → 4000 paires, 0 mismatch.

Résultats
- 23 tests (6 + 12 + 2 + 3) — 0 échec.
- Fonctionnel en production pour l’usage actuel.

Notes
- shellcheck possible plus tard (non prioritaire).
- Performances I/O OK (historiques courts: max 30 lignes).
