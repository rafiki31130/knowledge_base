# Règles de contribution

Ce dépôt est une **base de connaissances publiable**. Les règles ci-dessous
existent pour qu'il le reste, quel que soit le contributeur (humain ou
assistant).

## Principe directeur

> Si on ne pourrait pas publier la page sur un blog public, elle ne va pas ici.

En cas de doute : **anonymiser ou ne pas écrire**.

## Interdits explicites

- Noms d'environnements, de projets internes, de clients.
- Noms d'hôtes, de clusters, de sites, de zones réseau réels.
- IP, sous-réseaux, FQDN, URL internes.
- Comptes, identifiants, tokens, clés, hashs, mots de passe (même expirés).
- Chemins de fichiers contenant un identifiant interne.
- Captures d'écran non floutées.
- Références à des incidents, tickets, RUN, plannings, livrables clients.
- Détails d'architecture permettant d'identifier une infrastructure réelle.

## Bonnes pratiques

- Préférer des valeurs **génériques** : `indexer-01`, `10.0.0.0/24`,
  `example.com`, `user01`, `<tenant>`, `<region>`.
- Décrire des **principes** et des **patterns**, pas des configurations exactes
  copiées depuis un environnement.
- Pour une recherche / requête : montrer la **forme**, expliquer les champs,
  laisser les valeurs en placeholders.
- Citer ses sources officielles (docs vendeur, RFC, CVE…) quand pertinent.

## Style

- Markdown, une idée par fichier, titre H1 unique par page.
- Blocs de code annotés (` ```spl `, ` ```bash `, etc.).
- Français par défaut ; anglais accepté pour un sujet déjà cadré en anglais.

## Schémas et diagrammes — Mermaid par défaut

Dès qu'une fiche décrit une **architecture, un flux de données, une séquence d'échanges,
une machine à états ou une hiérarchie**, intégrer un schéma **[Mermaid](https://mermaid.js.org/)**
dans un bloc ` ```mermaid `. GitHub le rend nativement — c'est ce qui permet de saisir le
*quoi/comment* d'un coup d'œil sans dépendre d'une image externe.

- **La norme, c'est le schéma** : une page « conceptuelle » sans diagramme est l'exception à
  justifier, pas l'inverse. Préférer un petit diagramme juste à un long paragraphe descriptif.
- **Mermaid > image** : pas de capture d'écran ni de `.png` d'archi (versionnable, diffable,
  éditable en texte ; et une capture risque de fuiter du sensible — cf. interdits).
- **Fallback ASCII** seulement si Mermaid n'est pas adapté (table de correspondance, art figé).
- **Anonymisation identique** : les libellés de nœuds suivent les mêmes interdits que le texte
  (placeholders génériques `service-01`, `<tenant>`, jamais d'hôte/IP/FQDN réel).
- Syntaxe, types de diagrammes et pièges : [cheat-sheet Mermaid](./cheat-sheets/mermaid-obsidian.md).

## Format des liens

Le dépôt est lu sur **GitHub**. Seule la syntaxe markdown standard est rendue.

- **Liens internes** : markdown standard avec **chemin relatif** depuis le fichier courant.
  - Même dossier : `[texte](./autre-fiche.md)`
  - Parent : `[texte](../section/fiche.md)`
  - Ancre vers une section : `[texte](./fiche.md#nom-de-section)` (slug = lowercase, espaces→`-`, ponctuation supprimée).
- **Extension `.md` obligatoire.**
- **Wikilinks Obsidian `[[...]]` interdits** — non rendus par GitHub, s'affichent littéralement.
- **Liens externes** : URL complète https. Préférer des sources officielles (docs vendeur, RFC).

## Pas de duplication

- Une idée vit à un seul endroit du dépôt. Ailleurs : un lien.
- Si deux fiches commencent à se chevaucher, en extraire le tronc commun dans une troisième fiche que les deux référencent.
- Un court rappel inline reste acceptable s'il pointe vers la source.

## Workflow

- Commit direct sur `main`, pas de PR ni de revue obligatoire.
- Un commit = un sujet cohérent quand c'est possible.
- Si une page existante mélange du sensible et du générique, la corriger
  immédiatement (réécriture, pas seulement suppression — l'historique reste).

## Si du sensible a été commité par erreur

1. Réécrire la page pour purger le contenu.
2. Considérer que la donnée est **compromise** — la traiter comme telle dans
   l'environnement concerné (rotation, etc.).
3. Le simple `git revert` ne suffit pas : l'historique public garde la trace.
   Faire remonter pour décider d'une réécriture d'historique si nécessaire.
