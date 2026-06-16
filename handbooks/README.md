# Handbooks

## Objet

Ce dossier accueille des **handbooks thématiques** : livres Markdown courts,
**anonymisés et publiables**, qui consolident les bonnes pratiques, anti-patterns
et déclencheurs d'escalade d'un domaine technique pour un **profil de lecteur
ciblé** (typiquement un power user, pas un débutant ni un admin).

Un handbook n'est **pas** un tutoriel : il suppose le lecteur déjà à l'aise avec
le sujet. Il ancre les réflexes, pas les notions de base.

## Structure d'un handbook

Chaque handbook vit dans son propre sous-dossier :

```
handbooks/<slug-handbook>/
├── README.md            ← index + persona + scope + sommaire + sources globales + versioning
├── 00-<slug>.md         ← chapitre 0 (foundations / mise en contexte si applicable)
├── 01-<slug>.md         ← chapitre 1
├── 02-<slug>.md         ← ...
├── NN-<slug>.md         ← chapitre N
└── 99-<slug>.md         ← (optionnel) chapitre conclusif type cheatsheet
```

### `README.md` du handbook

Doit contenir, dans l'ordre :

1. **What this handbook is and isn't** — une page de cadrage.
2. **Persona** — qui devrait lire ça, prérequis implicites.
3. **Scope** — versions, périmètre, ce qui est explicitement hors scope.
4. **How to use this handbook** — chapitres indépendants ou ordre pédagogique.
5. **Table of contents** — liens markdown relatifs vers chaque chapitre.
6. **Conventions** — exemples placeholders, notation des commandes, citation des sources.
7. **Global sources** — pointeurs vers les références canoniques du domaine.
8. **Versioning note** — versions exactes contre lesquelles le handbook est écrit.

### Chapitres

Un fichier Markdown par chapitre, **préfixé `NN-`** (de `00-` à `99-`) pour
ordonner. Chaque chapitre est lisible indépendamment, dans la mesure du possible.

Chaque chapitre **se termine** par une section `## Sources` listant les
références canoniques utilisées dans le chapitre (liens markdown, URLs figées
à une version stable).

Les conventions de squelette de chapitre (sections obligatoires, longueur cible,
ton, exemples) sont fixées par le `README.md` du handbook lui-même : un handbook
peut imposer un template plus précis à ses chapitres (cf. spec éditoriale dans
le projet de cadrage côté wiki interne).

## Conventions de nommage

- **Slug du handbook** : kebab-case, descriptif et qualifié du profil cible.
  Exemples : `splunk-user-handbook`, `python-debugging-handbook`.
- **Slug d'un chapitre** : kebab-case, court, préfixé par `NN-` (deux chiffres).
  Exemples : `00-foundations.md`, `01-spl-search-anatomy.md`,
  `99-escalation-cheatsheet.md`.
- Pas d'espace dans les noms de fichier.
- Un H1 unique par fichier.

## Anonymisation (R7 — règle non négociable)

Ce repo est **public**. Aucun handbook ne doit contenir le moindre élément
identifiant une infra réelle :

- Aucun FQDN, hostname, IP, FQDN interne réel.
- Aucun nom d'organisation, ticket, projet client, nom de personne.
- Aucun chemin filesystem propriétaire qui révélerait une convention interne.
- Aucun nom d'app interne. Citer les apps officielles ou des génériques.

Substituts canoniques à privilégier (et à réutiliser tels quels par tous les
auteurs d'un même handbook pour cohérence) :

| Catégorie | Valeur canonique |
| --- | --- |
| Hostnames génériques | `host01`, `web01`, `db01`, `idx01`, `sh01` |
| Domaines | `example.com`, `corp.example.com` |
| IP / CIDR | `10.0.0.0/24`, `192.0.2.10` (RFC 5737), `2001:db8::/32` |
| Utilisateurs | `alice`, `bob`, `svc_app` |
| App / projet générique | `my_company_app` |

Un handbook spécialisé peut étendre cette table dans son `README.md` (cf.
exemples Splunk : `index`, `sourcetype`, `role`).

**Relecture obligatoire** avant tout commit : grep ciblé sur les identifiants
sensibles du domaine de l'auteur. Si du sensible a été commité, l'historique
GitHub est public — réécrire et tourner le secret, ne pas se contenter d'un
revert.

## Lien retour vers le pilotage projet

Les handbooks sont des **livrables publiables**. Leur pilotage (cadrage
éditorial, plan détaillé par chapitre, suivi des décisions chef de projet,
audits, phases de rédaction/test/relecture) vit dans le **wiki interne**
(non public), pas ici.

Seuls les fichiers Markdown du livre lui-même sont publiés dans ce dossier.

## Handbooks

| Handbook | Statut | Profil cible | Description courte |
| --- | --- | --- | --- |
| `splunk-user-handbook/` | Phase 2 — rédaction en cours | Power user SecOps / IT, Splunk Enterprise 9.x on-prem, SPL1 | 9 chapitres : foundations, SPL (4), dashboards, alerts, apps/KO/RBAC, escalation cheatsheet. Anglais. |
| `gouvernance-utilisateurs-splunk/` | Livré | Architecte / sysadmin senior Splunk, Splunk Enterprise 9.4.x on-prem, SHC | 8 chapitres : pourquoi gouverner, méthode de projet, quatre axes, findings empiriques 9.4.6, guide RBAC, guide WLM search heads, guide WLM indexers, recommandations chiffrées et glossaire. Français. |

> Le dossier `splunk-user-handbook/` sera créé par les agents Rédacteurs en
> phase 2 — il n'existe pas encore au moment où cette convention est posée.

## Ajouter un nouveau handbook

1. Créer `handbooks/<slug-handbook>/`.
2. Y déposer un `README.md` conforme à la structure ci-dessus.
3. Ajouter une ligne à la table « Handbooks » de ce fichier.
4. Ajouter `handbooks/` à l'index du `README.md` racine du repo si pas déjà fait.
