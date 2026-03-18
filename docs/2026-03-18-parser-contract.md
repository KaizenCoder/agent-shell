Contrat Parser — Mode Shell

Objectif
- Documenter le comportement de `_agent_shell_parse_response` et les cas couverts par les tests de contrat.

Point d’entrée
- Fichier: ~/.agent_shell/lib_api.sh:94
- Fonction: `_agent_shell_parse_response(response_json)`

Entrée attendue
- JSON Gemini `generateContent` (cas OK):
  - `candidates[0].content.parts[0].text` contient le texte brut généré par le modèle.
- JSON d’erreur (cas 429):
  - `{ "error": { "code": 429, "message": "... retry in N seconds" } }`

Règles de parsing
- Nettoyage backticks: supprime un éventuel préfixe de type ```lang\n (backticks d’ouverture) dans le texte.
- Découpage lignes: `raw.split("\n")`, lignes vides retirées.
- Description `desc`:
  - `lines[0]` si présent, sinon `"# commande"`.
- Commande `cmd`:
  - Concatène avec `&&` toutes les lignes qui ne commencent pas par `#`.
  - Peut être vide si aucune ligne de commande.
- Erreurs:
  - 429 → `status=RATE_LIMIT`, `wait=N` (extrait depuis le message), arrêt du parsing normal.
  - Autres erreurs → `status=ERROR`, `desc="# Erreur API: <extrait>"`, `cmd=''`.

Cas de test (fixtures)
- OK (2 lignes): `ok.json`
  - Texte: `# Affiche la date du jour\ndate`
  - Résultat: `desc="# Affiche la date du jour"`, `cmd="date"`, `status=OK`.
- Une seule ligne: `one_line.json`
  - Texte: `date`
  - Résultat: `desc="date"`, `cmd="date"`, `status=OK`.
- Description seule: `desc_only.json`
  - Texte: `# Juste une description sans commande`
  - Résultat: `desc="# Juste une description sans commande"`, `cmd=""`, `status=OK`.
- Backticks d’ouverture: `backticks.json`
  - Texte: ```bash\nls -l
  - Résultat: `desc="ls -l"`, `cmd="ls -l"`, `status=OK`.
- Rate limit: `error_429.json`
  - Résultat: `status=RATE_LIMIT`, `wait=5` (exemple).

Tests
- Script: ~/.agent_shell/tests/test_parser.sh:1
- Exécution: `bash ~/.agent_shell/tests/test_parser.sh`
- Offline, déterministes, zéro appel réseau.

Notes
- Le nettoyage des backticks vise le préfixe (fence d’ouverture) le plus courant renvoyé par le modèle.
- Le format historique reste inchangé; ces tests ciblent uniquement le parsing de la réponse API en mode shell.
