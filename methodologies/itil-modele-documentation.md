# Documenter un SI avec ITIL : Service Model, CI et CMDB

Une erreur fréquente est de documenter un service comme **une fiche plate** qui
décrit tout : l'hôte, les composants, la config, l'exposition, les dépendances.
Au-delà d'une certaine taille, cette fiche devient un fourre-tout illisible et
non maintenable. ITIL propose un modèle plus robuste : un service est un
**ensemble de Configuration Items (CI) reliés** dans une **CMDB**, et sa vue
d'articulation est un **Service Model**. Cette fiche décrit ce modèle de façon
générique, du plus léger (petite équipe) au plus complet (entreprise).

Gouvernance du **changement** associée : [itil-gouvernance-changement.md](./itil-gouvernance-changement.md).

## Les briques

| Terme ITIL | Définition | Répond à |
|---|---|---|
| **Configuration Item (CI)** | élément géré individuellement (service, appli, hôte, base, certificat, doc…) | « qu'est-ce que c'est, comment c'est configuré » |
| **CMDB** (Configuration Management Database) | référentiel des CI **et de leurs relations** | « qu'est-ce qui existe et comment c'est relié » |
| **CMS** (Configuration Management System) | la CMDB + les outils/vues au-dessus (fédération de plusieurs sources) | — |
| **Service Model / Service Map** | vue d'articulation d'un service : composants, dépendances, flux | « comment ça s'assemble » |
| **Service Catalogue** | catalogue des services offerts (vue *business* + vue *technique*) | « quels services, pour qui » |
| **Service Portfolio** | tous les services par cycle de vie : *pipeline* (en conception), *catalogue* (actifs), *retired* | « où en est chaque service » |
| **KEDB** (Known Error Database) | erreurs connues : cause racine + contournement | « pourquoi ça casse, comment contourner » |
| **DML** (Definitive Media Library) | source de vérité des binaires/code/configs (souvent : les dépôts) | « d'où vient l'artefact déployé » |
| **Baseline** | état figé et approuvé d'un CI à un instant T (point de référence/rollback) | « quel était l'état validé » |

## Le principe central : CI + relations, pas une fiche monolithe

Le savoir ne vit pas *dans* une grande fiche : il vit dans les **CI** et surtout
dans les **relations entre CI**. Une fiche fourre-tout, en langage ITIL, est un
CI à granularité trop grossière qui a avalé plusieurs CI distincts et leurs
relations.

Relations typées usuelles (les arêtes du Service Model) :

- `composant de` / `composé de` — appartenance au périmètre d'un service
- `hébergé sur` — tourne sur un CI d'infrastructure
- `dépend de` — dépendance fonctionnelle (la panne se propage)
- `utilise` / `consomme` — appelle un **service partagé**
- `exposé via` — chemin d'exposition (reverse proxy, passerelle)
- `versionné dans` — source de vérité (DML)

```text
        ┌──────────────────────── Service Model ─────────────────────┐
        │  Service "Paie"                                            │
        │                                                            │
        │   [appli-paie] ──utilise──► [base-paie] ──hébergé sur──► [db-01]
        │        │                                                   │
        │   exposé via                                          dépend de
        │        ▼                                                   ▼
        │   [reverse-proxy]  (service partagé, référencé)     [stockage-san]
        └────────────────────────────────────────────────────────────┘
```

Un service **partagé** (reverse proxy, base mutualisée, annuaire) est **un seul
CI**, **référencé** (relation `utilise`) par chaque service qui le consomme —
relation *many-to-many*. On ne le recopie jamais dans chaque service.

## La règle de granularité d'un CI

La question pratique « jusqu'où découper ? » a une réponse ITIL :

> On définit un CI au **grain auquel on veut le contrôler, le versionner et
> l'auditer indépendamment.** Ni trop fin (coût de maintenance des relations qui
> explose), ni trop gros (le fourre-tout).

Test concret : *« est-ce que je gère / versionne / déploie / audite cet élément
indépendamment ? »* → si oui, c'est son propre CI ; sinon, c'est une **section**
d'un autre CI. Un serveur applicatif avec son repo, sa version et son pipeline de
déploiement propres est un CI distinct de l'hôte qui le porte (lequel est un CI
d'infrastructure à part).

## Source unique de vérité

Un fait vit dans **un seul** CI ; partout ailleurs, **un lien** (une relation).
L'identité matérielle d'un hôte appartient à l'inventaire/CMDB d'infra ; la
config d'un composant à sa fiche ; les détails d'exposition au CI du reverse
proxy. Le Service Model **articule par pointeur**, il ne recopie pas le détail.
Un court résumé inline reste acceptable s'il pointe vers la source.

## Catalogue vs Portfolio

- **Service Catalogue** : ce qui est **disponible aujourd'hui**. Deux vues — la
  vue *business* (ce que voit le client : « messagerie », « sauvegarde ») et la
  vue *technique* (les CI/services support qui la réalisent).
- **Service Portfolio** : le **cycle de vie complet**, y compris les services en
  conception (*pipeline*) et retirés (*retired*). Classer les fiches par statut
  (en conception → actif → retiré) matérialise le portfolio.

## Vérification & audit de la CMDB

Une CMDB n'a de valeur que si elle **reflète la réalité**. Deux mécanismes :

- **Audit/vérification** : comparer périodiquement la CMDB à l'état réel
  (découverte automatique, ou contrôle manuel). En cas d'écart : **la doc se met
  à jour, pas l'inverse**.
- **Source générée** : pour l'inventaire factuel (hôtes, IP, VLAN), générer la
  page depuis l'outil qui fait foi plutôt que la maintenir à la main.

Un CI **retiré** n'est pas supprimé : il passe en statut *retired*, ses
relations historiques conservées (traçabilité). Pour ne pas casser les liens
entrants après une refonte, on laisse à l'ancien emplacement un **renvoi**
(redirection) vers la nouvelle structure.

## Du léger à l'entreprise

Le modèle se décline selon la taille de l'organisation.

| Aspect | Version *lean* (petite équipe) | Version entreprise |
|---|---|---|
| CMDB | dépôt de fiches Markdown + inventaire généré | outil CMDB dédié, **fédéré** (CMS), liens automatiques |
| Découverte | manuelle / scripts | *discovery* automatique (agents, scans) |
| Service Catalogue | une page d'index | portail de services, vue business/technique séparées, SLA attachés |
| Propriété des CI | implicite (l'équipe) | **CI owner** formel + RACI |
| Vérification | contrôle ponctuel | audits planifiés, réconciliation, indicateurs de qualité CMDB |

La logique de fond ne change pas : **CI + relations + source unique**. L'apparat
d'entreprise ajoute de l'**outillage**, de la **fédération** et de la
**gouvernance formelle** — utile à l'échelle, surdimensionné pour une petite
structure. Choisir le niveau selon le besoin réel de contrôle.

## ITIL 4 — où ça se range

ITIL 4 parle de **pratiques** (et non plus de « processus »). Le modèle ci-dessus
relève surtout de la pratique **Service Configuration Management**, dont la
finalité officielle est de *fournir un modèle des services montrant comment les
CI travaillent ensemble*. Elle s'inscrit dans le **Service Value System (SVS)** et
alimente toutes les autres pratiques (changement, incident, mise en production…),
détaillées dans [itil-gouvernance-changement.md](./itil-gouvernance-changement.md).

## À retenir

- Un service multi-composant = **un Service Model** (articulation) + des **CI**
  (composants), pas une fiche unique.
- Granularité d'un CI = **cycle de vie indépendant**.
- **Source unique + relations** ; les services partagés sont référencés, jamais
  recopiés.
- La CMDB doit être **vérifiée contre la réalité** ; un CI retiré se conserve.
- Le même modèle se décline du *lean* (fiches + liens) à l'entreprise (CMDB
  fédérée, discovery, gouvernance) — c'est le **niveau d'outillage** qui change,
  pas le principe.