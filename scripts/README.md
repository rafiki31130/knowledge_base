# Scripts

Scripts utilitaires génériques et réutilisables, prêts à adapter à un environnement.
Contenu anonymisé : aucune référence à une infrastructure réelle, valeurs en placeholders
(`bitbucket.corp.example`, `<PROJECT_KEY>`, `<tenant>`...).

Un script n'a sa place ici que s'il est **générique** : paramétré, sans hôte/IP/secret en
dur, utilisable tel quel par n'importe qui après substitution des placeholders. Un script
couplé à une infra précise va dans la doc d'exploitation privée, pas ici.

## Format d'une fiche script

Chaque script vit dans **son propre sous-dossier** avec :

1. Un **`README.md`** — rôle, pré-requis, paramètres, exemples d'usage, garde-fous, et au
   moins un **schéma Mermaid** du flux (cf. [`CONTRIBUTING.md`](../CONTRIBUTING.md#schémas-et-diagrammes--mermaid-par-défaut)).
2. Le **script** lui-même (et ses fichiers d'exemple : config, jeux de données factices).

## Scripts

- [Bitbucket — édition de masse de repos (Splunk)](./bitbucket-bulk-edit/README.md) — PowerShell.
  Applique des transformations regex sur des fichiers ciblés, dans les repos d'un projet
  Bitbucket Server/DC filtrés par regex. Modes Audit (dry-run avec diff) et Execute
  (commit + push + PR). Auth via le gestionnaire d'identifiants de l'OS.
