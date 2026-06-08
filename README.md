# Knowledge Base

Base de connaissances commune, lisible et corrigeable, sur des sujets techniques
récurrents (Splunk, investigations, concepts transverses). Sert de référence
partagée — ce qui est ici a vocation à avoir été relu / vérifié.

## Ce qu'on y met

- Principes de fonctionnement (« comment ça marche »).
- Fiches de référence (SPL, regex, formats de logs…).
- Recettes génériques (recherches d'investigation type, méthodes).
- Schémas conceptuels, lexiques, pièges connus.

## Ce qu'on n'y met pas

Ce dépôt **n'est pas** une documentation d'exploitation. Voir
[`CONTRIBUTING.md`](./CONTRIBUTING.md) pour les règles détaillées. En résumé :

- Pas de noms d'environnements, d'hôtes, d'utilisateurs, de chemins internes.
- Pas d'IP, de domaines, d'identifiants, de tokens, de secrets.
- Pas de description d'architecture spécifique à un client / à une infra.
- Pas de suivi de travaux en cours (tickets, RUN, incidents).

Si une information ne pourrait pas être publiée telle quelle sur Internet,
elle n'a pas sa place ici. Anonymiser ou reformuler.

## Arborescence

- [`splunk/`](./splunk) — Splunk : concepts, SPL, recherches génériques.
- [`methodologies/`](./methodologies) — Méthodes d'investigation, frameworks.
- [`concepts/`](./concepts) — Transverse : logs, regex, parsing, réseau…
- [`cheat-sheets/`](./cheat-sheets) — Aide-mémoire commandes par techno.

## Workflow

- Édition directe sur `main`, sans revue préalable.
- Commits clairs et autonomes (un sujet = un commit quand c'est possible).
- Toute info douteuse est anonymisée d'abord, ajoutée ensuite.
