# knowledge_base

Base de connaissances **publique et anonymisée** sur des sujets techniques
récurrents (Splunk, investigations, concepts transverses). Hébergée sur GitHub.

## Nature et distinction

| | knowledge_base | wiki |
|---|---|---|
| Visibilité | Public GitHub | Privé (git interne) |
| Contenu | Principes, patterns génériques | Exploitation, infra réelle |
| Audience | Tout le monde | Mainteneurs + agents internes |

Règle absolue : si une information identifie une infra, un environnement, un
client ou un utilisateur réel, elle va dans `wiki`,
pas ici.

## Anonymisation — non-négociable

Avant tout commit, vérifier l'absence de :

- Noms d'hôtes, IP, FQDN, domaines internes réels
- Noms d'environnements, projets ou clients
- Identifiants, tokens, clés, hashes (même expirés)
- Chemins contenant un identifiant interne
- Références à des incidents, tickets ou livrables réels

Substituts à utiliser : `indexer-01`, `10.0.0.0/24`, `example.com`,
`user01`, `<tenant>`, `<region>`.

Si du sensible a été commité : **la page est compromise** — réécrire, ne pas
se contenter d'un revert (l'historique GitHub est public).

Détails complets → [`CONTRIBUTING.md`](./CONTRIBUTING.md)

## Workflow git

```bash
git pull                         # toujours avant d'éditer
# ... éditions ...
git add <fichiers ciblés>        # jamais git add -A
git commit -m "<scope>: <sujet>" # un commit = un sujet cohérent
git push
```

Branche unique : `main`. Pas de PR, pas de revue obligatoire.

## Conventions de fichiers

- Noms : `kebab-case.md`, pas d'espaces
- Un fichier = une idée ; pas de duplication (lien vers la source)
- Titre H1 unique par page
- Blocs de code annotés : ` ```spl `, ` ```bash `, ` ```json `…
- **Schémas en Mermaid par défaut** : toute archi/flux/séquence/état s'illustre par un bloc
  ` ```mermaid ` (rendu nativement par GitHub), pas par une image — ASCII en fallback seul.
  Libellés anonymisés comme le reste. Détails : [cheat-sheet Mermaid](./cheat-sheets/mermaid-obsidian.md)
- Liens internes : markdown standard avec chemin relatif + extension `.md`
  (ex. `[texte](../concepts/parsing.md)`) — wikilinks `[[...]]` interdits
- Langue : français par défaut

## Arborescence

```
knowledge_base/
├── splunk/          — concepts, SPL, recherches génériques
├── methodologies/   — méthodes d'investigation, frameworks
├── concepts/        — transverse : logs, regex, réseau…
├── cheat-sheets/    — aide-mémoire commandes par techno
└── scripts/         — scripts utilitaires génériques (1 sous-dossier/script + schéma)
```
