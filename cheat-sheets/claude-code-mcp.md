---
title: Claude Code & MCP
category: cheat-sheets
tags: [claude-code, mcp, cli, llm, tooling, cheat-sheet]
created: 2026-06-08
---

# Claude Code & MCP — Cheat-sheet

## À quoi ça sert

Claude Code est un assistant de développement en ligne de commande. Le **Model Context
Protocol (MCP)** lui permet de se connecter à des serveurs externes qui exposent des
outils et des ressources. Cette fiche couvre, de façon **générique** : l'usage de la CLI
`claude`, la configuration de serveurs MCP, et le diagnostic d'une connexion MCP.

Tous les noms de serveurs, hôtes et jetons ci-dessous sont des placeholders
(`<server>`, `https://mcp.example.com`). Aucune valeur réelle ne doit figurer dans une
fiche publique : les secrets vont en variable d'environnement ou en gestionnaire dédié.

## Commandes de base

### CLI `claude`

```bash
claude                               # ouvrir une session interactive
claude "<prompt>"                    # lancer une session avec un prompt initial
claude --print "<prompt>"            # mode non interactif : imprime la réponse et sort
claude -p "<prompt>"                 # alias court de --print (scriptable)
claude --continue                    # reprendre la dernière session du dossier
claude --resume                      # choisir une session passée à reprendre
claude --model <model>               # forcer un modèle pour la session
claude --help                        # liste complète des options
```

```bash
# Mode non interactif + format de sortie (utile en script / CI)
claude -p "<prompt>" --output-format json     # text | json | stream-json
```

### Commandes dans la session (slash commands)

```text
/mcp          # état des serveurs MCP connectés (et outils exposés)
/help         # aide intégrée
/clear        # réinitialiser le contexte de la conversation
/config       # ouvrir la configuration
```

### Configuration des serveurs MCP

Les serveurs MCP se déclarent sous la clé `mcpServers`, à la racine d'un fichier de
configuration dont le nom dépend de la portée : **`.mcp.json`** pour la portée projet
(partagé, commité dans le dépôt) et **`~/.claude.json`** pour la portée utilisateur.
Deux transports courants : **stdio** (le serveur est un processus local lancé par
Claude) et **http** (serveur distant joint par HTTP).

```jsonc
{
  "mcpServers": {
    // Transport stdio : un binaire/local lancé en sous-processus
    "<server>": {
      "command": "<binaire>",
      "args": ["<arg1>", "<arg2>"],
      "env": {
        "API_TOKEN": "${API_TOKEN}"   // référence une variable d'env, pas la valeur
      }
    },
    // Transport http : serveur distant
    "<server-http>": {
      "type": "http",
      "url": "https://mcp.example.com",
      "headers": {
        "Authorization": "Bearer ${MCP_TOKEN}"
      }
    }
  }
}
```

```bash
# Gestion des serveurs via la CLI (selon version) :
claude mcp list                      # lister les serveurs MCP configurés
claude mcp get <server>              # détails d'un serveur
claude mcp add --transport http <server> https://mcp.example.com   # serveur HTTP (URL positionnelle)
claude mcp add <server> -- <commande> [args...]                    # serveur stdio (-- sépare la commande)
claude mcp remove <server>           # retirer un serveur
```

### Debug d'un serveur MCP

```bash
# 1. Vérifier l'état de connexion dans la session
#    -> taper /mcp : un serveur doit apparaître "connected"

# 2. Tester un serveur stdio à la main (échange JSON-RPC sur stdin/stdout) :
#    le serveur doit répondre à initialize puis lister ses outils.
#    Exemple d'appel "tools/list" (forme JSON-RPC) :
{"jsonrpc":"2.0","id":1,"method":"tools/list"}

# 3. Augmenter la verbosité des logs de la CLI
claude --debug "<prompt>"            # traces détaillées (dont l'I/O MCP)
```

Côté serveur HTTP, les méthodes MCP standards utiles au diagnostic : `initialize`,
`tools/list` (outils exposés), `resources/list` (ressources). Un serveur qui ne répond
pas à `tools/list` n'exposera aucun outil dans la session.

## Pièges fréquents

- **Secret en clair dans le fichier de config** : ne jamais écrire un token littéral
  dans le `.mcp.json` (ou `~/.claude.json`). Le référencer via `${VAR}` (variable
  d'environnement) ou un gestionnaire de secrets. Une config versionnée peut fuiter.
- **Portée de la config** : une même clé peut exister au niveau projet et utilisateur ;
  la plus spécifique l'emporte. Un serveur « invisible » vient souvent d'un fichier édité
  au mauvais niveau.
- **JSON invalide = aucun serveur chargé** : une virgule en trop dans le fichier de
  config (`.mcp.json` / `~/.claude.json`) invalide tout le bloc `mcpServers`. Valider le
  JSON après édition.
- **Transport stdio qui échoue silencieusement** : si `command` n'est pas dans le `PATH`
  ou plante au démarrage, le serveur reste « non connecté ». Le lancer à la main pour voir
  l'erreur, puis `--debug`.
- **Serveur HTTP : auth et CORS/headers** : un 401 vient des `headers` (token), un timeout
  d'une URL injoignable. Tester l'URL avec `curl` avant de blâmer la CLI.
- **Confondre `tools/list` vide et serveur déconnecté** : un serveur peut être connecté
  mais n'exposer aucun outil (config incomplète côté serveur). `/mcp` distingue les deux.

## Voir aussi

- [GitHub CLI (gh)](./gh-cli.md) — autre outil CLI scriptable, mode non interactif similaire.
- [Secrets & SSH](./secrets-ssh.md) — gérer les jetons MCP (`${VAR}`) hors du fichier de config.
- [Docker](./docker.md) — exécuter un serveur MCP en conteneur (transport stdio/http).
