---
title: Splunk RBAC (rôles, capabilities, héritage, plancher [default])
category: cheat-sheets
tags: [splunk, rbac, authorize, roles, capabilities, least-privilege, cheat-sheet]
created: 2026-06-27
---

# Splunk RBAC — Cheat-sheet

> **Version** : validé empiriquement sur **Splunk Enterprise 9.4.6**. Les textes
> de la spec `authorize.conf` sont stables 9.1 → 10.x, mais le **comportement de
> la stanza `[default]`** (et de `<cap> = disabled`, §4) est à **re-vérifier sur
> 10.x** avant de s'y fier en production.

## À quoi ça sert

Le contrôle d'accès Splunk (`authorize.conf`) attribue à chaque **rôle** trois
familles de droits : des **capabilities** (verbes d'action), des **restrictions
de données** (`srchIndexes*`, `srchFilter`, `srchTimeWin`) et des **quotas** de
recherche. Un utilisateur porte un ou plusieurs rôles ; un rôle peut en importer
d'autres (`importRoles`). Cette fiche sert à raisonner « least-privilege » : ce
qu'un rôle accorde par défaut, comment les droits se composent par héritage, et
comment **retirer** une capability accordée par le socle sans casser l'instance.

Trois mécanismes composent les droits effectifs d'un utilisateur :

1. **`importRoles`** — héritage transitif et cumulatif entre rôles.
2. **Multi-rôles directs** — un user porte N rôles ; les droits se combinent.
3. **Stanza `[default]`** — un plancher de quotas/limites *et* de quelques
   capabilities, hérité par tout rôle qui ne les redéclare pas (§2).

> **Piège transverse** : la sortie REST distingue les valeurs **locales** des
> valeurs **`imported_*`**. Pour les **capabilities** et les **index**,
> `imported_*` est **effectif**. Pour les **quotas**, `imported_*` est **purement
> informationnel** : l'enforcement réel = valeur **locale** du rôle final (ou le
> défaut `[default]`). Auditer les capabilities via `imported_capabilities`, mais
> les quotas via les valeurs **locales** des rôles assignés.

---

## 1. Rôles built-in

Sur une instance Splunk Enterprise **9.4.x fraîche**, six rôles sont livrés par
le paquet, déclarés dans `$SPLUNK_HOME/etc/system/default/authorize.conf` (jamais
d'override local sur une instance neuve). Chaînes `importRoles` et capabilities
clés observées en lecture REST native :

Compteurs ci-dessous : **caps déclarées** dans la stanza (≠ effectives, qui ajoutent les 5 du plancher `[default]`). Stanzas exhaustives juste après.

| Rôle | `importRoles` | Caps déclarées | Quotas (`srchJobsQuota` / `srchDiskQuota`) | Index (`srchIndexesAllowed`) | Note |
|---|---|---|---|---|---|
| `user` | *(aucun)* | 25 (→ **28 effectives**) — dont `search`, `accelerate_search`, `run_collect` | `3` / `100` *(du `[default]`)* | `*` (non-internes) | Socle utilisateur : peut chercher. |
| `power` | `user` | 17 (dont `rtsearch`, `schedule_search`, `edit_sourcetypes`) — **pas `search` en local** | `10` / `500` | `*` | Power user : obtient `search` **via** `user`. |
| `admin` | `power` ; `user` | 113 | `50` / `10000` | `*` ; `_*` (internes inclus) | Administration. Importe explicitement les **deux**. |
| `can_delete` | *(aucun)* | 1 (`delete_by_keyword`, → **6 effectives**) | `3` / `100` *(du `[default]`)* | — | Requis pour la commande SPL `delete`. À assigner ponctuellement. |
| `splunk-system-role` | `admin` | 0 (**154** effectives via `admin`) | — | — | Rôle système interne. Ne pas assigner à des humains. |
| `splunk_system_upgrader` | *(aucun)* | 7 (→ **12 effectives**) | `3` / `100` *(du `[default]`)* | — | Rôle système (migrations d'upgrade). Ne pas assigner. |

Points qui surprennent souvent :

- **`power` n'a pas `search` en local** : il l'obtient par héritage de `user`
  (`importRoles = user`, écrit en dur dans le paquet). Un user portant seulement
  `power` peut donc chercher.
- **`admin` importe `power` ET `user`** (`importRoles = power;user`).
  Conséquence : `search` lui arrive par deux chemins. Supprimer `user` casse
  quand même `admin` (cf. §5, cascade `DELETE`).
- **`admin` couvre les internes** (`_*`) ; `user`/`power` non (`*` seul →
  non-internes uniquement). Pour qu'un rôle voie `_internal`/`_audit`, lui donner
  `_*` ou nommer l'index explicitement.

```ini
# Forme d'un rôle métier from-scratch (least-privilege) — etc/system/local/authorize.conf
[role_myrole]
# pas d'importRoles : on ne tire aucune cap d'un built-in
search                = enabled
srchIndexesAllowed    = index_app ; index_summary
srchJobsQuota         = 3          # redéclarer : l'héritage n'enforce pas les quotas (§3)
srchDiskQuota         = 100
```

### Stanzas complètes des rôles built-in (référence 9.4.6)

Contenu **réel** du paquet (`$SPLUNK_HOME/etc/system/default/authorize.conf`),
identique sur toute install 9.4.6 fraîche. Ce sont les capabilities
**déclarées** dans chaque rôle ; les capabilities **effectives** ajoutent les 5
du plancher `[default]` (§2) pour les rôles qui ne les déclarent pas — ex. `user`
déclare 25 caps → **28 effectives** avec `edit_own_objects` / `list_all_objects`
/ `schedule_rtsearch`. Idem les quotas absents d'une stanza = valeur du `[default]`.

```ini
[role_user]
# importRoles : aucun
change_own_password          = enabled
edit_search_schedule_window  = enabled
get_metadata                 = enabled
get_typeahead                = enabled
input_file                   = enabled
list_inputs                  = enabled
output_file                  = enabled
upload_lookup_files          = enabled
request_remote_tok           = enabled
rest_apps_view               = enabled
rest_properties_get          = enabled
rest_properties_set          = enabled
search                       = enabled
accelerate_search            = enabled
list_accelerate_search       = enabled
pattern_detect               = enabled
list_metrics_catalog         = enabled
list_tokens_own              = enabled
export_results_is_visible    = enabled
run_collect                  = enabled
run_mcollect                 = enabled
run_dump                     = enabled
run_sendalert                = enabled
run_custom_command           = enabled
rest_access_server_endpoints = enabled
srchIndexesAllowed = *
srchIndexesDefault = main

[role_can_delete]
# importRoles : aucun
delete_by_keyword         = enabled
cumulativeSrchJobsQuota   = 0
cumulativeRTSrchJobsQuota = 0
deleteIndexesAllowed      = *

[role_power]
importRoles = user
edit_messages                      = enabled
schedule_search                    = enabled
metric_alerts                      = enabled
embed_report                       = enabled
edit_dispatch_as                   = enabled
rtsearch                           = enabled
edit_sourcetypes                   = enabled
edit_statsd_transforms             = enabled
search_process_config_refresh      = enabled
edit_log_alert_event               = enabled
run_msearch                        = enabled
run_dump                           = enabled
run_sendalert                      = enabled
run_custom_command                 = enabled
rest_access_server_endpoints       = enabled
list_field_filter                  = enabled
run_commands_ignoring_field_filter = enabled
srchIndexesAllowed = *
srchIndexesDefault = main
srchDiskQuota             = 500
srchJobsQuota             = 10
rtSrchJobsQuota           = 20
cumulativeSrchJobsQuota   = 100
cumulativeRTSrchJobsQuota = 200

[role_admin]
importRoles = power;user
edit_messages                  = enabled
accelerate_datamodel           = enabled
admin_all_objects              = enabled
edit_tokens_settings           = enabled
change_authentication          = enabled
change_audit                   = enabled
edit_bookmarks_mc              = enabled
create_external_lookup         = enabled
edit_external_lookup           = enabled
edit_deployment_client         = enabled
list_deployment_client         = enabled
edit_deployment_server         = enabled
list_deployment_server         = enabled
list_search_head_clustering    = enabled
dispatch_rest_to_indexers      = enabled
edit_authentication_extensions = enabled
edit_cmd                       = enabled
edit_upload_and_index          = enabled
edit_tcp_stream                = enabled
list_dist_peer                 = enabled
edit_dist_peer                 = enabled
edit_field_filter              = enabled
list_field_filter              = enabled
edit_restmap                   = enabled
edit_forwarders                = enabled
edit_indexerdiscovery          = enabled
edit_httpauths                 = enabled
edit_indexer_cluster           = enabled
edit_input_defaults            = enabled
list_introspection             = enabled
edit_local_apps                = enabled
edit_monitor                   = enabled
edit_tokens_own                = enabled
edit_roles                     = enabled
edit_scripted                  = enabled
edit_search_concurrency_all    = enabled
edit_search_head_clustering    = enabled
edit_search_server             = enabled
edit_search_scheduler          = enabled
edit_search_schedule_priority  = enabled
edit_tokens_all                = enabled
list_tokens_all                = enabled
edit_certificates              = enabled
list_certificates              = enabled
edit_spl2_permissions          = enabled
list_indexer_cluster           = enabled
list_pipeline_sets             = enabled
list_search_scheduler          = enabled
list_settings                  = enabled
edit_server                    = enabled
edit_user_seed                 = enabled
edit_splunktcp                 = enabled
edit_splunktcp_ssl             = enabled
edit_splunktcp_token           = enabled
edit_tcp                       = enabled
edit_udp                       = enabled
edit_telemetry_settings        = enabled
edit_user                      = enabled
edit_view_html                 = enabled
edit_web_settings              = enabled
get_diag                       = enabled
indexes_edit                   = enabled
install_apps                   = enabled
license_edit                   = enabled
license_tab                    = enabled
license_view_warnings          = enabled
refresh_application_licenses   = enabled
list_forwarders                = enabled
list_indexerdiscovery          = enabled
list_httpauths                 = enabled
rest_apps_management           = enabled
restart_splunkd                = enabled
restart_reason                 = enabled
run_debug_commands             = enabled
list_token_http                = enabled
edit_token_http                = enabled
web_debug                      = enabled
search_process_config_refresh  = enabled
edit_server_crl                = enabled
edit_storage_passwords         = enabled
list_storage_passwords         = enabled
edit_encryption_key_provider   = enabled
never_lockout                  = enabled
never_expire                   = enabled
list_health                    = enabled
edit_health                    = enabled
apps_restore                   = enabled
apps_backup                    = enabled
fsh_manage                     = enabled
fsh_search                     = enabled
edit_workload_pools            = enabled
list_workload_pools            = enabled
select_workload_pools          = enabled
edit_workload_rules            = enabled
list_workload_rules            = enabled
list_workload_policy           = enabled
edit_workload_policy           = enabled
edit_metric_schema             = enabled
edit_metrics_rollup            = enabled
list_cascading_plans           = enabled
list_remote_output_queue       = enabled
list_remote_input_queue        = enabled
list_ingest_rulesets           = enabled
edit_ingest_rulesets           = enabled
capture_ingest_events          = enabled
edit_log_alert_event           = enabled
edit_global_banner             = enabled
edit_web_features              = enabled
edit_kvstore                   = enabled
upload_mmdb_files              = enabled
use_remote_proxy               = enabled
edit_manager_xml               = enabled
merge_buckets                  = enabled
srchIndexesAllowed = *;_*
srchIndexesDefault = main;os
srchFilter         = *
srchTimeWin        = 0
srchTimeEarliest   = 0
srchDiskQuota             = 10000
srchJobsQuota             = 50
rtSrchJobsQuota           = 100
cumulativeSrchJobsQuota   = 200
cumulativeRTSrchJobsQuota = 400

[role_splunk-system-role]
importRoles = admin
# aucune capability ni quota en propre : tout vient de l'import admin

[role_splunk_system_upgrader]
# importRoles : aucun — caps en propre (le reste = plancher [default])
edit_indexer_cluster        = enabled
list_indexer_cluster        = enabled
list_search_head_clustering = enabled
list_settings               = enabled
upgrade_splunk_idxc         = enabled
upgrade_splunk_shc          = enabled
use_remote_proxy            = enabled
```

> `splunk-system-role` et `splunk_system_upgrader` sont des **rôles système**
> (clustering, migrations d'upgrade) — **ne pas les assigner à des humains**.

> **Couches d'apps (la stanza `system/default` n'est pas « toute » la stanza)** :
> les apps groupées de Splunk Enterprise **étendent** des rôles via la précédence
> de conf (`etc/apps/*/default/authorize.conf`). En 9.4.6, `[role_admin]` reçoit
> **+4 caps** hors `system/default` : `edit_modinput_journald` (app
> `journald_input`), `upgrade_splunk_shc` + `upgrade_splunk_idxc` (app
> `splunk-rolling-upgrade`), `splunk_mobile_administration` (app
> `splunk_secure_gateway`) → **admin effectif = 113 + 4 = 117 caps**. Et
> `[role_splunk_system_upgrader]` est défini **entièrement** par l'app
> `splunk-rolling-upgrade` (rien dans `system/default`). **À retenir** : un rôle
> peut être assemblé sur **plusieurs fichiers** ; pour voir sa stanza *effective*
> réelle, utiliser `splunk btool authorize list role_<nom>` plutôt que de lire un
> seul fichier.
>
> **Aucune capability n'est jamais déclarée `= disabled`** dans un rôle livré
> (system ou apps) : le modèle Splunk d'origine est **purement additif**
> (`= enabled` seulement). Le retrait par `= disabled` (§4) est un mécanisme de
> *précédence de conf* que les defaults Splunk n'illustrent nulle part — d'où la
> formulation « `disabled` has no effect » de la doc, écrite dans l'optique
> additive `importRoles`.

---

## 2. La stanza `[default]` d'`authorize.conf`

`[default]` (pas `[general]` — celle-là est dans `server.conf`) est un **plancher
universel** : tout rôle qui ne redéclare pas un attribut **hérite** la valeur du
`[default]`, y compris un rôle créé **from-scratch** (`importRoles` vide). Ce
plancher est **distinct du rôle `user`** : un rôle qui n'importe pas `user`
reçoit quand même les valeurs du `[default]`.

Contenu réel du `[default]` système en 9.4.6 (lu via `btool`) :

```ini
# $SPLUNK_HOME/etc/system/default/authorize.conf  (NE JAMAIS éditer ce fichier — §4)
[default]
# --- capabilities accordées par le plancher ---
run_collect          = enabled
run_mcollect         = enabled
edit_own_objects     = enabled
list_all_objects     = enabled
schedule_rtsearch    = enabled
# --- scalaires (quotas / limites / filtre) ---
srchJobsQuota             = 3
rtSrchJobsQuota           = 6
srchDiskQuota             = 100
cumulativeSrchJobsQuota   = 50
cumulativeRTSrchJobsQuota = 100
srchFilterSelecting       = true
srchMaxTime               = 100days
# (srchTimeWin n'est PAS dans le natif ; un override l'ajoute)
```

- **Le `[default]` ne porte ni `srchIndexesAllowed`, ni `srchFilter`, ni
  `importRoles`** : ces deux premiers sont déclarés **par rôle** (`[role_user]`,
  `[role_admin]`…). Le plancher ne pose que des quotas/limites **et** les cinq
  capabilities ci-dessus.
- **Conséquence gouvernance** : un rôle « illimité » qu'on croit sans contrainte
  est en réalité plafonné à **3 jobs concurrents** dès qu'on oublie de redéclarer
  `srchJobsQuota`. Et un rôle from-scratch hérite silencieusement de
  `run_collect`, `run_mcollect`, etc. — c'est exactement le sujet de la §4.

> **Piège REST** : les capabilities du plancher n'apparaissent dans la lecture
> REST d'un rôle fraîchement créé **qu'après un restart** de `splunkd` — alors
> que le moteur les applique déjà. Toujours croiser **REST + test fonctionnel +
> restart**, sinon on conclut à tort que le plancher ne s'applique pas.

---

## 3. Héritage par type de droit

Chaque famille de droit se compose selon sa **propre** règle. Synthèse (observée
empiriquement en 9.4.6) :

| Famille | Règle via `importRoles` | Multi-rôles directs sur un user |
|---|---|---|
| **Capabilities** | Union, transitive, cumulative, **non révocable** dans l'enfant | Union |
| **`srchIndexesAllowed` / `Default`** | **Union additive** (le plus large gagne — *broadest*) | Union |
| **`srchIndexesDisallowed`** | Propagé et **autoritatif** : le `disallowed` d'un parent gagne même sur un `allowed` local de l'enfant (*most-restrictive*) | *Most-restrictive* : le `disallowed` d'**un seul** rôle bloque pour tout le user |
| **`srchFilter`** | Combinaison **OR** (le plus large gagne) | **OR** |
| **`srchTimeWin`** | *Broadest* (le moins restrictif gagne) ; `0` = illimité non écrasable, `-1` écrasable | **`min()`** — le **plus restrictif** gagne (asymétrie vs multi-parents) |
| **Quotas non-cumulatifs** (`srchJobsQuota`, `rtSrchJobsQuota`, `srchDiskQuota`) | **Aucune valeur héritée ne s'impose** comme plancher ; `imported_*` informationnel | **`max()`** sur la chaîne (le plus permissif gagne) |
| **Quotas cumulatifs** (`cumulative*SrchJobsQuota`) | **Non hérités** et non appliqués aux users de l'enfant ; requièrent le toggle global `enable_cumulative_quota` | n/a (plafond **collectif** par rôle) |
| **ACL d'objet** (metadata `default.meta`/`local.meta`) | **Héritage actif** : l'ACL est évaluée sur les rôles importés | Union des rôles effectifs (importés inclus) |

Trois invariants à retenir :

1. **Capabilities = additif pur** : on construit par ajout, jamais par
   soustraction *via `importRoles`*. Pour exclure une cap héritée d'un autre
   rôle : **ne pas importer** ce rôle. (Le retrait du plancher `[default]` relève
   d'un autre plan — §4.)
2. **Quotas = pas d'héritage enforceable** : **redéclarer** les quotas dans
   chaque rôle métier final. `imported_*Quota` est trompeur ; en multi-rôles
   c'est le **plus permissif** (`max()`) qui gagne, jamais le plus restrictif.
3. **`srchFilter` = OR** : un `srchFilter = *` (ou absent) sur un rôle **annule**
   les restrictions des autres. Bannir `srchFilter = *` (traité comme littéral) —
   laisser le champ **vide** à la place.

```mermaid
flowchart TD
    U["Utilisateur (roles = role_a ; role_b)"]
    U --> RA["role_a"]
    U --> RB["role_b"]
    RA -->|importRoles| P["role_parent"]
    P --> D["Stanza [default]<br/>(plancher universel)"]
    RA --> D
    RB --> D
    D -. capabilities .-> EC["Capabilities : UNION (additif, non révocable via importRoles)"]
    D -. srchIndexesAllowed .-> EI["Index allowed : UNION (broadest)"]
    D -. srchIndexesDisallowed .-> ED["Index disallowed : most-restrictive (propagé)"]
    D -. srchFilter .-> EF["srchFilter : OR"]
    D -. srchTimeWin .-> ET["srchTimeWin : min (rôles directs) / max (multi-parents)"]
    D -. quotas .-> EQ["Quotas non-cumulatifs : max() sur la chaîne"]
```

---

## 4. Retirer une capability héritée du plancher `[default]`

> Cœur de la fiche. Un rôle from-scratch hérite les capabilities `enabled` du
> `[default]` (`run_collect`, `run_mcollect`, `edit_own_objects`,
> `list_all_objects`, `schedule_rtsearch`). On veut pouvoir en **retirer** une en
> least-privilege — sans jamais éditer `system/default`.

**Verdict (9.4.6)** : oui, `<cap> = disabled` retire la capability héritée du
plancher — au **niveau rôle** (ciblé) ou en **override `system/local [default]`**
(global). Le retrait est réel et fonctionnel (commande SPL refusée, `FATAL:
insufficient privileges`).

### Pourquoi cela ne « contredit pas la doc »

La documentation officielle énonce que les capabilities sont *« additives, non
révocables »* et que `<cap> = disabled` *« has no effect »*. **Cet énoncé reste
vrai** : il décrit l'**instanciation / héritage de rôle via `importRoles`** — une
cap qu'un rôle tire d'un **autre rôle importé** n'est effectivement pas
révocable, et `= disabled` n'y révoque rien.

Le retrait observé opère sur un **autre plan : la précédence de configuration**
(`system/local` > `system/default`, et stanza spécifique > `[default]`). Une cap
dont la valeur vient du **plancher `[default]`** est une **valeur par défaut
d'attribut**, soumise à cette précédence. **La doc ne couvre pas ce plan** — elle
n'est pas fausse, elle décrit autre chose.

### `= disabled` n'est pas un no-op

Prouvé par deux rôles jumeaux ne différant que de cette ligne :

| Ligne dans la stanza du rôle | `run_collect` effectif | Commande `collect` |
|---|---|---|
| **absente** | **présent** (hérité du plancher `[default]`) | OK |
| `<cap> = disabled` | **absent** | FATAL |

Si `= disabled` était un no-op équivalent à l'omission, les deux lignes
donneraient le même résultat. Elles diffèrent : `= disabled` **écrase activement**
la valeur héritée du plancher. C'est la **précédence d'attribut**, pas
l'instanciation `importRoles` que vise la doc.

### Matrice des syntaxes (9.4.6, rôle from-scratch sans `importRoles`)

| Valeur de la ligne | Warning `… had value '<v>' - only 'enabled' is valid. Ignoring…` | Cap retirée ? | Mécanisme |
|---|---|---|---|
| `= disabled` | **non** (valeur reconnue) | **oui** | retrait actif par précédence |
| `=` (vide) · `= false` · `= 0` | **oui** | **oui** | valeur rejetée *comme activateur* (seul `enabled` active) → cap non activée |
| `= enabled` | non | non (présente) | activation |
| **ligne absente** | non | non (présente) | plancher `[default]` actif |

**Le warning ne signifie PAS « cap conservée ».** Le message
`Capability '<cap>' had value '<v>' - only 'enabled' is valid. Ignoring...`
apparaît sur une **valeur invalide** (vide / `false` / `0`), **pas** sur
`= disabled`. Il signifie « cette *valeur* n'est pas un activateur valide » :
comme seul `enabled` active une capability, la cap finit **retirée quand même**
si aucune autre source ne l'accorde. (En override `[default]`, ce warning est
émis **une fois par rôle**, pas une fois globalement.)

### Recommandation de configuration

- **Pour retirer une cap du plancher : utiliser `<cap> = disabled`** — valeur
  reconnue, silencieuse, intention explicite. **Jamais** la valeur vide (warning
  parasite, ~1× par rôle).
  - **Au niveau rôle** (ciblé, le plus propre, recommandé en least-privilege) :
    déclarer `<cap> = disabled` dans chaque rôle-type concerné.
  - **En override global** `system/local [default]` : retire la cap à tous les
    rôles **sauf** ceux qui la déclarent en propre (cf. ci-dessous).
- **Ne jamais éditer `system/default`** (interdit par Splunk, écrasé à
  l'upgrade) — override en `system/local` uniquement.

### Portée du levier global

`system/local [default] <cap> = disabled` **ne retire pas** la cap aux built-in
`user`/`power` : ils déclarent la cap en propre dans leur **propre** stanza
(`[role_user]`/`[role_power]`), qui prime sur le `[default]` durci. Le levier
global ne mord que sur les caps **purement héritées du plancher**. En
least-privilege où les utilisateurs ne portent **que** des rôles from-scratch
(jamais `user`/`power` directement), cet override les retire partout.

```ini
# Retrait ciblé au niveau rôle — etc/system/local/authorize.conf
[role_myrole]
search        = enabled
run_collect   = disabled      # retire la cap héritée du plancher [default]
run_mcollect  = disabled
```

```ini
# Retrait global — etc/system/local/authorize.conf
[default]
run_collect   = disabled      # retiré partout SAUF rôles le déclarant en propre (user/power)
```

```mermaid
flowchart TD
    Q["Résolution de la capability <cap> pour un rôle"]
    Q --> L{"system/local : stanza du rôle<br/>déclare <cap> ?"}
    L -->|"= enabled"| ON["Cap ACTIVE"]
    L -->|"= disabled"| OFF["Cap RETIRÉE (écrase le plancher)"]
    L -->|"=, false, 0"| OFFW["Cap RETIRÉE + warning Ignoring"]
    L -->|"ligne absente"| DEF{"system/local [default]<br/>déclare <cap> ?"}
    DEF -->|"= disabled"| OFF2["Cap RETIRÉE (override global)"]
    DEF -->|"absente"| SYS["system/default [default]<br/>(plancher : <cap> = enabled)"]
    SYS --> ON
```

---

## 5. Autres mécaniques fondamentales

- **`POST` REST = SET destructif.** `POST /services/authorization/roles/<role>`
  avec une liste partielle de `capabilities` **écrase** toutes les caps non
  listées (HTTP 200, aucun avertissement). Un POST « pour ajouter une cap » à un
  rôle existant peut le ramener de 28 caps à 2. **Pattern obligatoire : GET →
  merge → POST complet.** Les noms de rôle sont normalisés en **lowercase +
  underscore**.
- **Cascade `DELETE` sur un built-in.** `DELETE /services/authorization/roles/user`
  retourne HTTP 200, sans garde-fou. Conséquence en chaîne : `power` perd son
  `importRoles = user`, `admin` perd les capabilities qui remontaient de `user`
  (dont `search`) → recherches admin en « insufficient permission » jusqu'à
  reconstruction manuelle. Ne jamais supprimer un rôle built-in.
- **`defaultRolesIfMissing` = fallback, pas plancher cumulé.** Ce paramètre
  (`authentication.conf`, SAML) attribue un rôle **uniquement** quand le mapping
  ne renvoie aucun rôle — il ne **s'ajoute pas** aux rôles mappés. Pour un vrai
  « rôle plancher » commun à tous, passer par un groupe IdP *all-users* mappé
  explicitement. **Garde-fou** : ne **jamais** mettre `admin` dans
  `defaultRolesIfMissing` (Splunk utilise temporairement `admin` pour traiter
  l'info de groupe SAML → escalade accidentelle).
- **`enable_cumulative_quota` = interrupteur global.** Les quotas cumulatifs
  (`cumulativeSrchJobsQuota`, `cumulativeRTSrchJobsQuota`) sont **inertes** tant
  que `limits.conf [search] enable_cumulative_quota = true` n'est pas posé. À
  déclarer **uniquement sur le rôle final** assigné (non hérité via
  `importRoles`).

---

## Pièges fréquents

- **Croire qu'un rôle from-scratch est « vierge »** : il hérite le plancher
  `[default]` (5 caps + quotas). Vérifier en REST **après restart** + test
  fonctionnel.
- **Lire le warning `Ignoring` comme « cap conservée »** : faux — la cap est
  retirée (valeur rejetée comme activateur). Utiliser `= disabled` pour éviter le
  warning.
- **Éditer `system/default`** : interdit, écrasé à l'upgrade. Override en
  `system/local`.
- **Compter sur l'héritage pour plafonner un quota** : il n'enforce rien.
  Redéclarer dans chaque rôle final.
- **`POST` REST partiel sur un rôle** : écrase les caps absentes. Toujours GET →
  merge → POST.
- **`srchFilter = *`** : annule tout filtre (OR). Laisser vide.
- **`*` en `srchIndexesAllowed`** : ne couvre **pas** les internes. Utiliser `_*`
  ou nommer (`_internal;_audit`).

## Voir aussi

- [Splunk (administration / CLI)](./splunk-admin.md) — CLI `splunk`, `btool`,
  `_internal`, start/stop.
- [Splunk — concepts & SPL](../splunk/README.md) — architecture, indexers, search
  heads, langage de recherche.
- [Secrets & SSH](./secrets-ssh.md) — récupération de tokens via `op` pour les
  appels REST authentifiés.
