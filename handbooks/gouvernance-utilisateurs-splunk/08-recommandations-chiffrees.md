# Chapitre 8 — Recommandations chiffrées, registre, glossaire

> Ce chapitre consolide les valeurs chiffrées proposées par le guide,
> le registre des comportements dangereux qui alimentent la boucle
> pédagogique, et le glossaire. Toutes les valeurs portent la mention
> **« à adapter au contexte »** — elles sont l'état de l'art pour un
> SHC d'environ mille utilisateurs et doivent être calibrées sur la
> baseline d'usage réelle.

## 1. Paliers de quotas par profil

### Table de référence

| Paramètre | `quota_base` | `quota_plus` | `quota_max` |
| --- | --- | --- | --- |
| `srchJobsQuota` | 5 | 15 | 30 |
| `srchDiskQuota` (MB) | 500 | 2 000 | 5 000 |
| `srchTimeWin` (s) | 86 400 (1 j) | 604 800 (7 j) | 2 592 000 (30 j) |
| `rtSrchJobsQuota` | 0 (pas de RT) | 2 | 6 |
| `cumulativeSrchJobsQuota` | 0 (off) | 0 (off) | 0 ou 200 (admin) |

### Distribution attendue

| Profil | Palier | Volume attendu sur 1 000 users |
| --- | --- | --- |
| Consultatif (lecture seule) | `quota_base` | ~70 % |
| Power utilisateur (planifie) | `quota_plus` | ~20 % |
| Owner applicatif (écrit) | `quota_max` | ~5 % |
| Admin délégué | `quota_max` + cumulatif | ~1 % |

### Critères d'adaptation au contexte

- **Mesurer pendant 2 à 4 semaines** la concurrence ad-hoc, scheduled,
  et la durée moyenne d'une recherche (R.1.04 et R.1.05 du chapitre 5).
- **Si un utilisateur consultatif typique consomme déjà 6+ jobs
  concurrents** régulièrement, le palier `base=5` est sous-évalué.
- **Si moins de 5 % des utilisateurs ont besoin du `quota_max`**, c'est
  cohérent. Si plus de 15 %, le modèle des profils types est à
  questionner.
- **Pour un SHC à plus de 5 000 utilisateurs**, augmenter chaque
  palier proportionnellement n'est **pas** la bonne réponse — il vaut
  mieux affiner les profils (introduire un `quota_premium` entre `plus`
  et `max` par exemple).

## 2. Pourcentages de pool WLM côté Search Head

### Table de référence

Catégorie `search` à 80 % du CPU/RAM total, `ingest` à 15 %, `misc` à
5 %.

| Pool | `cpu_weight` | `mem_weight` | `default_category_pool` |
| --- | --- | --- | --- |
| `admin` | 15 | 15 | 0 |
| `scheduled` | 30 | 30 | 0 |
| `ad_hoc` | 35 | 35 | **1** |
| `bulk` | 10 | 10 | 0 |
| `accel` | 10 | 10 | 0 |
| `ingest_default` | 1 | 1 | **1** |
| `misc_default` | 1 | 1 | **1** |

### Critères d'adaptation

- **Si le pool `scheduled` sature** régulièrement, augmenter sa part —
  ou mieux, étaler la planification côté saved searches.
- **Si `ad_hoc` est sous pression** (B.3.02), augmenter sa part à
  40-45 % aux dépens de `scheduled`.
- **Le pool `admin`** ne doit jamais descendre en dessous de 10-15 % —
  c'est ce qui garantit qu'un admin peut diagnostiquer une saturation.
- **Pour un cluster à GPU pour accélération** : augmenter `accel` à
  15-20 % et bien isoler le pool.

## 3. Pourcentages de pool WLM côté indexer

### Table de référence

| Pool | Catégorie | `cpu_weight` / `mem_weight` |
| --- | --- | --- |
| `ingest_default` | ingest | 70 / 70 |
| `ingest_priority` | ingest | 20 / 20 |
| `ingest_bulk` | ingest | 10 / 10 |
| `search_peer_default` | search_peer | 100 / 100 |
| `misc_default` | misc | 100 / 100 |

### Critères d'adaptation

- **Si les sourcetypes sensibles** représentent plus de 20 % du volume
  d'ingestion, augmenter `ingest_priority` à 30 %.
- **`ingest_bulk` reste contraint** délibérément — c'est ce qui
  protège l'ingestion sensible quand un dump bulk arrive.

## 4. Durées de monitor-only

### Recommandations par axe

| Axe | Durée monitor-only | Justification |
| --- | --- | --- |
| RBAC — bascule des composites | 1 à 2 semaines | Capter un cycle hebdo de saved searches |
| WLM Search Head — `alert` | 2 à 4 semaines | Capter un cycle mensuel (clôture, reporting) |
| WLM Indexer — `alert` | 2 à 4 semaines | Capter la variabilité d'ingestion (cycles métier) |
| Sensibilisation — vague pilote | 4 semaines | Mesurer le taux de récidive (K1) |

### Critères d'extension

- **Étendre à 4 semaines** si le SHC traverse un cycle mensuel
  sensible (clôture comptable, reporting fin de mois).
- **Étendre à 6 semaines** si une migration ou un freeze est planifié
  pendant la fenêtre.

## 5. Seuils du cycle de vie SAML

### Table de référence

| Seuil | Valeur | Justification |
| --- | --- | --- |
| Inactivité avant désactivation | 90 jours | NIST SP 800-63B, Microsoft Entra, Okta |
| Quarantaine avant hard delete | 90 jours supplémentaires | Permet réactivation, traitement KO |
| Total avant suppression | 180 jours | Cycle standard IAM |

### Critères d'adaptation

- **Pour une organisation très distribuée** géographiquement,
  envisager 120 jours d'inactivité (pour absorber les saisonniers).
- **Pour une organisation à très forte rotation**, 60 jours peut
  suffire — mais il faut un workflow de réactivation rapide.

## 6. Registre des comportements dangereux

Le registre consolidé classifie les comportements observables côté
plateforme par criticité. Il alimente :

- le pilier détection de la sensibilisation pédagogique ;
- les saved searches d'audit en croisière ;
- les seuils des règles WLM.

### Échelle de criticité

| Niveau | Critère | Délai d'action |
| --- | --- | --- |
| 🔴 Critique | Peut casser la plateforme en une opération, exfiltrer un secret, ou détruire de la preuve indexée | Immédiat — garde-fou de procédure obligatoire |
| 🟠 Élevé | Dégrade fortement un axe : saturation progressive, fuite non authentifiée, élévation indirecte | Court terme — quick win de durcissement |
| 🟡 Moyen | Piège latent ou ambiguïté de modélisation, induit une fausse assurance lors d'un audit | Moyen terme — KEDB + intégrer aux SPL d'audit |
| ⚪ Info | Comportement à connaître pour auditer correctement, sans danger propre | Veille — note d'audit |

### Registre (extrait — vingt-trois comportements)

| Id | Comportement | Criticité | Pourquoi dangereux |
| --- | --- | --- | --- |
| D-01 | DELETE d'un rôle built-in (`user`/`can_delete`) autorisé sans confirmation, casse `admin` par cascade | 🔴 | Restauration manuelle obligatoire |
| D-02 | POST sur un rôle existant = SET destructif | 🔴 | Remplace toute la liste de capabilities sans warning |
| D-03 | DELETE d'un rôle utilisé supprime les users en cascade | 🔴 | Pas d'avertissement, perte des ressources privées |
| D-04 | `list_storage_passwords` / `edit_storage_passwords` sur un rôle non-IAM | 🔴 | Exfiltration de secrets |
| D-05 | `can_delete` / `delete_by_keyword` hors compte admin nominatif | 🔴 | Suppression d'événements indexés, perte de preuve |
| D-06 | `admin_all_objects` / `edit_roles` / `change_authentication` hors `admin_iam` | 🔴 | Bypass ACL, pivot vers tout droit |
| D-07 | `srchFilter=*` dans un rôle annule tout filtre restrictif (OR multi-rôles) | 🟠 | Un user multi-rôles voit toutes les données |
| D-08 | `rtsearch` sur `power` (ou rôle hérité) | 🟠 | Coût CPU/I/O massif à l'échelle |
| D-09 | `schedule_search` / `schedule_rtsearch` sur `power` | 🟠 | Multiplication non maîtrisée de scheduled |
| D-10 | `accelerate_search` / `accelerate_datamodel` sur `user`/`power` | 🟠 | Stockage indexer + I/O en continu |
| D-11 | `embed_report` sur `power` | 🟠 | URLs publiques d'embed sans authentification |
| D-12 | Quota local absent → `max()` multi-rôles + défaut 3 | 🟠 | Fausse assurance de plafond |
| D-13 | `cumulativeSrchJobsQuota` sur parent inerte sans toggle `enable_cumulative_quota` | 🟡 | Double piège : placement et toggle |
| D-14 | `srchTimeWin=0` (illimité) chez un parent masque la trace d'une borne | 🟡 | L'audit croit à une borne absente |
| D-15 | Capability héritée non-révocable (`<cap>=disabled` no-op) | 🟡 | Fausse croyance de révocation |
| D-16 | `srchIndexesAllowed=*` ne couvre PAS les internes `_*` | 🟡 | Couverture totale = `*;_*` |
| D-17 | Syntaxe `-_audit` / `!_audit` invalide (no-op) | 🟠 | Exclusion qui n'exclut rien |
| D-18 | `srchIndexesDisallowed` — précédence et héritage actifs | 🟡 | Levier fiable d'exclusion structurelle |
| D-19 | Permissions d'app/objet héritées via `importRoles` | 🟡 | ACL d'objet propagée aux descendants |
| D-20 | `run_script` / `rest_properties_set` sur rôle non-admin | 🟠 | Code arbitraire / bypass UI |
| D-21 | Normalisation lowercase des rôles → collisions invisibles | ⚪ | `MyRole` et `myrole` collisionnent silencieusement |
| D-22 | `splunk list role` ne filtre pas ; `btool` ne montre pas l'état fusionné | ⚪ | Méthodologie audit doit s'appuyer sur REST |
| D-23 | Rôle orphelin / `importRoles` vers rôle inexistant | 🟡 | Chaîne d'héritage rompue après DELETE |

### Routage des comportements vers les canaux

| Criticité | Canal | Action |
| --- | --- | --- |
| 🔴 Critique | Alerte SOC + notification admin SHC | Investigation, traitement incident. Pas de boucle pédagogique. |
| 🟠 Élevé | Notification pédagogique (Splunk Web Messages + email digest) | Observation + explication + alternative. Agrégation dashboard admin. |
| 🟡 Moyen | Dashboard de tendance | Consulté par les admins. Nudge utilisateur seulement si répétition. |
| ⚪ Info | Inventaire d'audit périodique | Pas de signal temps réel. |

## 7. Cinq KPI mesurables pour la sensibilisation

| KPI | Définition | Cible |
| --- | --- | --- |
| **K1** — Taux de récidive | Utilisateur qui répète le même comportement à plus de 30 jours | Diminue dans le temps après notification |
| **K2** — Temps de correction | Délai moyen entre la notification et l'arrêt observable | < 14 jours |
| **K3** — Nombre d'occurrences par comportement | Tendance plateforme par semaine | Stable ou décroissante |
| **K4** — Couverture | % de comportements 🟠 effectivement routés vers un canal pédagogique | > 90 % |
| **K5** — Taux d'ouverture | % des messages Splunk Web Messages ouverts | > 60 % |

## 8. Quinze recherches SPL d'audit consolidées

Les quinze recherches d'audit A-01 à A-12 ci-dessous portent sur les
vingt-trois comportements dangereux. Toutes sont conçues pour être
saved searches programmées avec routage selon la criticité du
comportement détecté.

### A-01 — Capabilities à risque par rôle

(détaillée comme R.1.02 au chapitre 5).

### A-02 — Rôles sans quota local

```spl
| rest /services/authorization/roles splunk_server=local
| where match(title, "^metier_") OR match(title, "^owner_") OR match(title, "^admin_")
| where isnull(srchJobsQuota) OR srchJobsQuota="" OR srchJobsQuota="0"
| table title imported_roles srchJobsQuota imported_srchJobsQuota
```

Cible D-12.

### A-03 — Audit du toggle `enable_cumulative_quota`

```spl
| rest /services/configs/conf-limits/search splunk_server=local
| table enable_cumulative_quota
| eval verdict = case(
    enable_cumulative_quota="true", "ON",
    enable_cumulative_quota="false", "OFF",
    isnull(enable_cumulative_quota), "DEFAULT (off)",
    true(), "?")
```

Cible D-13.

### A-04 — Rôles `srchFilter=*`

```spl
| rest /services/authorization/roles splunk_server=local
| where srchFilter="*"
| table title srchFilter imported_roles
```

Cible D-07.

### A-04bis — Couverture `*` vs `_*`

```spl
| rest /services/authorization/roles splunk_server=local
| eval has_star = if(mvfind(srchIndexesAllowed, "*")>=0, 1, 0)
| eval has_internal = if(mvfind(srchIndexesAllowed, "_*")>=0
    OR mvfind(srchIndexesAllowed, "_audit")>=0, 1, 0)
| where has_star=1 AND has_internal=0
| table title srchIndexesAllowed
```

Cible D-16.

### A-04ter — Syntaxes d'exclusion invalides

```spl
| rest /services/authorization/roles splunk_server=local
| eval has_minus = if(mvfind(srchIndexesAllowed, "-*")>=0, 1, 0)
| eval has_bang = if(mvfind(srchIndexesAllowed, "!*")>=0, 1, 0)
| where has_minus=1 OR has_bang=1
| table title srchIndexesAllowed
```

Cible D-17.

### A-04quater — Rôles avec `srchIndexesDisallowed`

```spl
| rest /services/authorization/roles splunk_server=local
| where isnotnull(srchIndexesDisallowed) AND srchIndexesDisallowed!=""
| table title srchIndexesAllowed srchIndexesDisallowed imported_srchIndexesDisallowed
```

Cible D-18 (inventaire utile).

### A-05 — Rôles sans borne `srchTimeWin`

```spl
| rest /services/authorization/roles splunk_server=local
| where match(title, "^metier_") OR match(title, "^owner_")
| where srchTimeWin="0" OR srchTimeWin="-1" OR isnull(srchTimeWin)
| table title srchTimeWin imported_srchTimeWin
```

Cible D-14.

### A-06 — Chaînes d'héritage `importRoles`

```spl
| rest /services/authorization/roles splunk_server=local
| where mvcount(imported_roles)>0
| eval chain = mvjoin(imported_roles, " -> ")
| table title chain
| sort title
```

Cible D-15, D-23.

### A-07 — Capabilities admin-only ailleurs

```spl
| rest /services/authorization/roles splunk_server=local
| eval all_caps = mvappend(capabilities, imported_capabilities)
| mvexpand all_caps
| search all_caps IN ("admin_all_objects","edit_roles","change_authentication",
    "list_storage_passwords","edit_storage_passwords","can_delete","delete_by_keyword")
  AND NOT title IN ("admin","admin_iam","can_delete")
  AND NOT match(title, "^audit_")
| stats values(all_caps) as caps_admin_only count by title
| sort -count
```

Cible D-04, D-05, D-06.

### A-08 — Utilisateurs multi-rôles

```spl
| rest /services/authentication/users splunk_server=local
| where mvcount(roles)>1
| table title realname roles type
```

Cible D-03, D-12 (combinaisons à risque).

### A-09 — Chaîne `power → user` intacte

```spl
| rest /services/authorization/roles/power splunk_server=local
| eval imports_user = if(mvfind(imported_roles, "user")>=0, "OK", "CASSEE")
| table title imported_roles imports_user
```

Cible D-01 (détection de cascade).

### A-10 — Audit des modifications de rôles via `_audit`

```spl
search index=_audit (action=edit_role OR action=create_role OR action=delete_role) earliest=-30d
| table _time user action role old_capabilities new_capabilities
| sort -_time
```

Cible D-01, D-02.

### A-11 — ACL d'objets permissives

```spl
| rest /servicesNS/-/-/saved/searches splunk_server=local
| rename "eai:acl.perms.read" as perms_read
        "eai:acl.perms.write" as perms_write
        "eai:acl.sharing" as sharing
        "eai:acl.app" as app
| where sharing="global" OR mvfind(perms_read, "*")>=0
| table app title sharing perms_read perms_write
| sort app title
```

Cible D-19.

### A-12 — Doublons de casse dans les rôles

```spl
| rest /services/authorization/roles splunk_server=local
| eval title_lower = lower(title)
| stats values(title) as variantes count by title_lower
| where count > 1
```

Cible D-21.

## 9. Glossaire

| Terme | Définition |
| --- | --- |
| **Rôle Splunk** | Enveloppe portant capabilities, accès index, quotas, et héritage. Déclaré dans `authorize.conf`. |
| **Capability** | Permission atomique Splunk (`search`, `schedule_search`, `rtsearch`, etc.). |
| **`importRoles`** | Mécanique d'héritage purement additive entre rôles. |
| **`srchIndexesAllowed`** | Liste blanche d'index. `*` ne couvre pas les internes. |
| **`srchIndexesDisallowed`** | Liste noire d'index. Précédence absolue. S'hérite via `importRoles`. |
| **`srchFilter`** | Fragment SPL appliqué automatiquement aux recherches d'un rôle. Combinaison OR multi-rôles. |
| **`srchJobsQuota`** | Plafond de jobs concurrents historiques par user. Non hérité. `max()` multi-rôles. |
| **`rtSrchJobsQuota`** | Plafond de jobs concurrents real-time. |
| **`srchDiskQuota`** | Plafond d'espace dispatch dir en MB. |
| **`srchTimeWin`** | Fenêtre temporelle max d'une recherche, en secondes. `-1` = illimité. |
| **`cumulativeSrchJobsQuota`** | Plafond collectif (toggle `enable_cumulative_quota`). |
| **Atomique** | Rôle mono-responsabilité — `data_*` / `feature_*` / `app_*` / `quota_*`. Jamais assigné directement à un user (sauf rôle plancher). |
| **Composite** | Rôle assigné aux utilisateurs. Aucune capability propre. `importRoles` des atomiques + redéclare quotas localement. |
| **Profil type** | Famille de composites (`metier_consultatif_*`, `metier_exploit_*`, `owner_app_*`, `admin_*`). |
| **Palier** | Niveau de quotas (`base`/`plus`/`max`) défini par le cadrage. |
| **Auto-mapping** | Attribution automatique d'un rôle Splunk au user dont l'IdP émet un groupe de nom égal. Toggle `enableAutoMappedRoles`. |
| **`roleMap_`** | Mapping explicite groupe IdP → rôle Splunk, maintenu à la main. |
| **`defaultRolesIfMissing`** | Filet de sécurité quand l'IdP n'émet aucun groupe mappé. Toujours `role_no_access` ; jamais `admin`. |
| **Rôle plancher** | Rôle attribué à tout utilisateur authentifié, via un groupe IdP « all-users ». Capabilities + index communs. Sans quota local. |
| **ACL** | Access Control List des knowledge objects, vit dans les metadata, hors `authorize.conf`. |
| **Knowledge object** | Saved search, dashboard, datamodel, macro, lookup, eventtype. |
| **Cycle de vie SAML** | Politique de désactivation après 90 j d'inactivité + hard delete après 90 j de quarantaine, avec traitement des KO orphelins. |
| **Pool WLM** | Enveloppe de ressources CPU / mémoire par cgroup. |
| **Catégorie WLM** | `search` / `ingest` / `misc` (+ `search_peer` côté indexer). |
| **Admission rule** | `[search_filter_rule:*]`. Évaluée avant exécution. Actions : `filter`, `queue`. |
| **Workload rule** | `[workload_rule:*]`. Placement + monitoring. Actions : placement implicite, `move`, `abort`, `alert`. |
| **`default_category_pool`** | Pool par défaut d'une catégorie. Obligatoire pour chaque catégorie. |
| **Cgroup** | Mécanisme Linux d'isolation des ressources. C'est ce qui applique réellement les pools. |
| **Cluster master** | Nœud de coordination du cluster d'indexers. Source de vérité de la configuration des peers. |
| **Cluster bundle** | Configuration commune des peers, propagée par `splunk apply cluster-bundle`. |

## 10. Sources et références canoniques

### Splunk

- [Securing Splunk Enterprise 9.4](https://help.splunk.com/en/splunk-enterprise/administer/secure-splunk-enterprise/9.4)
- [Admin Manual 9.4](https://help.splunk.com/en/splunk-enterprise/administer/admin-manual/9.4)
- [authorize.conf spec 9.4](https://help.splunk.com/en/data-management/splunk-enterprise-admin-manual/9.4/configuration-file-reference/9.4.5-configuration-file-reference/authorize.conf)
- [authentication.conf spec 9.4](https://help.splunk.com/en/data-management/splunk-enterprise-admin-manual/9.4/configuration-file-reference/9.4.5-configuration-file-reference/authentication.conf)
- [server.conf spec 9.4](https://help.splunk.com/en/data-management/splunk-enterprise-admin-manual/9.4/configuration-file-reference/9.4.5-configuration-file-reference/server.conf)
- [SAML SSO 9.4](https://help.splunk.com/en/splunk-enterprise/administer/manage-users-and-security/9.4/use-saml-as-an-authentication-scheme-for-single-sign-on)
- [Workload Management 9.4](https://help.splunk.com/en/splunk-enterprise/administer/manage-workloads/9.4)
- [Indexer Clusters 9.4](https://help.splunk.com/en/splunk-enterprise/administer/manage-indexers-and-indexer-clusters/9.4)
- [Splunk Validated Architectures](https://docs.splunk.com/Documentation/Splunk/latest/Architecture/WhatisaSplunkValidatedArchitecture)
- [Splunk Lantern](https://lantern.splunk.com/)
- [Splunk Blog — Best practices for Workload Management](https://www.splunk.com/en_us/blog/platform/best-practices-for-using-splunk-workload-management.html)

### Références IAM externes

- [NIST SP 800-63B — Digital Identity Guidelines](https://pages.nist.gov/800-63-3/sp800-63b.html)
- NIST SP 800-53 AC-5 (Separation of Duties) et AC-6 (Least Privilege)
- Microsoft Entra ID — lifecycle management documentation
- Okta — lifecycle management documentation
