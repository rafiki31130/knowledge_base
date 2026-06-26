# Chapitre 4 — Findings empiriques Splunk 9.4.6

> Ce chapitre consolide les comportements observés sur Splunk Enterprise
> 9.4.6 qui **divergent** de la documentation officielle ou la
> précisent significativement. Chaque finding est documenté sous la
> forme : hypothèse documentée, test mené, résultat observé,
> conséquence pour la gouvernance. C'est la matière à citer pour
> défendre une décision technique face à une contre-proposition mal
> informée.
>
> Tous les findings ci-dessous ont été observés empiriquement sur un
> lab Splunk Enterprise **9.4.6** single-instance Linux (kernel
> cgroupsv2). Quand la divergence porte sur la documentation officielle
> Splunk 9.4, la source documentaire est citée.


```table-of-contents
```
## Comment lire un finding

Chaque finding suit la même structure :

- **Hypothèse documentée** : ce qu'on attend du comportement selon la
  documentation officielle (avec lien).
- **Test mené** : la procédure pour reproduire l'observation (REST,
  SPL, CLI).
- **Résultat observé** : ce que le binaire 9.4.6 fait réellement.
- **Conséquence pour la gouvernance** : pourquoi ce finding change la
  façon de concevoir le modèle.

## Famille RBAC

### F-RBAC-01 — Non-révocabilité d'une capability héritée

**Hypothèse documentée.** La documentation Splunk
[Roles and capabilities 9.4](https://help.splunk.com/en/splunk-enterprise/administer/secure-splunk-enterprise/9.4/define-roles-on-the-splunk-platform/about-defining-roles-with-capabilities)
décrit `importRoles` comme un mécanisme d'héritage. Il serait
raisonnable d'attendre qu'une capability importée puisse être révoquée
au niveau du rôle enfant par une déclaration explicite — c'est ainsi
que fonctionnent les systèmes Allow/Deny d'autres éditeurs (AWS IAM
notamment).

**Test mené.** Soit deux rôles `r_parent` et `r_child`.

```ini
[role_r_parent]
capabilities = search;schedule_search;rtsearch
srchIndexesAllowed = main

[role_r_child]
importRoles = r_parent
capabilities = search;schedule_search
# Tentative 1 : déclaration explicite
rtsearch = disabled
```

On crée un utilisateur portant `r_child` et on observe sa capacité à
lancer une recherche real-time via REST :

```bash
curl -sk -u <user>:<pw> \
  https://<sh>:8089/services/search/jobs \
  -d 'search=index=main' \
  -d 'search_mode=realtime' \
  -d 'earliest_time=rt' -d 'latest_time=rt'
```

**Résultat observé.** Le job real-time est accepté. `rtsearch` reste
**effective** au runtime. La déclaration `rtsearch = disabled` est
stockée littéralement dans `etc/system/local/authorize.conf` sans
warning dans `splunkd.log`. Le test a été reproduit avec d'autres
formes (omission pure, `rtsearch =`, `rtsearch = 0`, `rtsearch =
false`) — tous équivalents au comportement nominal hérité.

L'héritage est donc **purement additif** : aucune mécanique de
soustraction au niveau de l'enfant.

**Conséquence pour la gouvernance.** La révocation se fait **au
niveau du parent atomique**, jamais par soustraction dans un
composite. Si on ne veut pas qu'un composite puisse planifier des
recherches real-time, on **n'importe pas** l'atomique `feature_rt`.
On ne tente pas de le désactiver après import.

Cela contraint le design du modèle hybride : chaque capability
sensible doit être **isolée dans son propre atomique** pour pouvoir
être incluse ou exclue, jamais retirée après inclusion.

### F-RBAC-02 — Quotas non hérités, `max()` multi-rôles

**Hypothèse documentée.** La sortie REST
`/services/authorization/roles` expose des champs `imported_*` pour
les quotas : `imported_srchJobsQuota`, `imported_srchDiskQuota`,
`imported_rtSrchJobsQuota`. Un lecteur raisonnable attend que ces
quotas hérités s'appliquent à un utilisateur du rôle enfant.

**Test mené.** Soit un atomique `quota_low` portant
`srchJobsQuota=1`, un rôle `r_user` qui l'importe sans redéclarer son
propre quota :

```ini
[role_quota_low]
srchJobsQuota = 1

[role_r_user]
importRoles = quota_low
capabilities = search
srchIndexesAllowed = main
```

On crée un utilisateur `u_test` portant `r_user` et on lance trois
recherches historiques concurrentes via REST.

**Résultat observé.** Les **trois recherches sont admises**. La
sortie REST sur `r_user` montre bien `imported_srchJobsQuota=1` mais
le binaire 9.4.6 **n'applique pas** ce plafond. La valeur effective
est le défaut système `srchJobsQuota=3` de la stanza `[default]` de
`authorize.conf`, parce que `r_user` ne redéclare pas sa propre valeur.

**Test complémentaire — règle `max()` multi-rôles.** Soit deux rôles
attribués directement à un utilisateur, l'un avec
`rtSrchJobsQuota=2`, l'autre avec `rtSrchJobsQuota=6`. On lance
quatre recherches real-time concurrentes :

- résultat observé : 4 RUNNING / 0 QUEUED — le plafond effectif est
  `max(2, 6) = 6`, jamais le minimum.

Un test avec `cumulativeRTSrchJobsQuota` confirme la même règle, et
ce plafond cumulatif n'est appliqué que si le toggle
`limits.conf [search] enable_cumulative_quota = true` est activé.

**Conséquence pour la gouvernance.** Toute conception du modèle de
quotas doit poser deux règles :

1. Les quotas **se redéclarent localement** dans chaque rôle final
   assigné à un utilisateur. Aucun rôle composite ne doit hériter
   « passivement » de ses quotas. Les atomiques `data_*`, `feature_*`,
   `app_*` ne portent **jamais** de quota.
2. La garantie de plafond se construit par **discipline d'attribution
   SAML** (un utilisateur n'a qu'un seul composite à la fois sauf cas
   validés). Sans cette discipline, l'effet `max()` ouvre la porte à
   un cumul non maîtrisé.

C'est la **fragilité par construction** de la couche quotas, et c'est
précisément ce que WLM (axe 4, chapitres 6-7) vient compenser : WLM
plafonne la ressource consommée, pas le nombre de jobs admis.

### F-RBAC-03 — `*` ne couvre pas les index internes

**Hypothèse documentée.** Pour un lecteur familier des conventions
wildcards Unix ou des expressions régulières, `srchIndexesAllowed=*`
suggère « tous les index ».

**Test mené.** On déploie deux rôles avec respectivement
`srchIndexesAllowed=*` et `srchIndexesAllowed=*;_*`, attribués à des
utilisateurs distincts. Chaque utilisateur lance
`| stats count by index` sur la durée maximale possible.

**Résultat observé.** L'utilisateur à `*` voit zéro événement sur
`_audit`, `_internal`, `_telemetry` et autres `_*`. L'utilisateur à
`*;_*` voit l'ensemble. Le wildcard `*` **n'inclut pas** les index
internes en 9.4.6.

**Test complémentaire.** Nommer `_audit` explicitement dans
`srchIndexesAllowed = _audit` n'ouvre que `_audit`, pas les autres
internes. Il faut soit `*;_*` (couverture totale), soit énumérer les
internes nécessaires.

**Conséquence pour la gouvernance.** Tout rôle « audit »
(`role_audit_inspector`, `data_audit`) doit déclarer explicitement
`_audit` (et selon le besoin `_internal`, `_telemetry`) dans son
`srchIndexesAllowed`. Tout rôle métier ne porte pas `*` — il déclare
ses index nominaux. Le wildcard `*` est réservé aux rôles
techniques d'administration.

### F-RBAC-04 — `srchIndexesDisallowed` prévaut et s'hérite

**Hypothèse.** La documentation 9.4 indique que
`srchIndexesDisallowed` prend précédence sur `srchIndexesAllowed` au
sein d'un rôle. Le comportement multi-rôles et l'héritage via
`importRoles` n'étaient pas documentés sans ambiguïté.

**Test mené.** Trois sous-tests : précédence intra-rôle (un même rôle
porte `srchIndexesAllowed=idx_a;idx_b` et
`srchIndexesDisallowed=idx_b`), héritage (un rôle enfant importe un
parent porteur de `Disallowed`), combinaison multi-rôles (un
utilisateur porte deux rôles, l'un autorisant `idx_b`, l'autre
l'interdisant).

**Résultat observé.**

- Précédence intra-rôle : `idx_b` est **invisible** comme attendu.
- Héritage : `srchIndexesDisallowed` **se propage** via `importRoles`
  et reste **effectif** chez l'enfant. Le champ REST
  `imported_srchIndexesDisallowed` existe (ce qui infirme une
  hypothèse de la littérature communautaire qui le supposait absent).
- Multi-rôles : la règle est **most-restrictive** — le rôle qui
  interdit gagne face au rôle qui autorise (logique inverse de la
  règle `max()` des quotas).

**Conséquence pour la gouvernance.** `srchIndexesDisallowed` est un
levier **fiable** d'exclusion structurelle qu'on peut poser au
niveau d'un atomique `data_*` et qui se propage proprement aux
composites. C'est notamment l'outil pour exclure `_audit` des rôles
métier non-audit, alors même que `srchIndexesAllowed` inclurait `*;_*`
pour des raisons historiques.

### F-RBAC-05 — Syntaxe `-_audit` invalide

**Hypothèse.** Plusieurs documentations communautaires suggèrent que
`srchIndexesAllowed=*;-_audit` exclut `_audit` du wildcard.

**Test mené.** Un rôle avec `srchIndexesAllowed=*;-_audit`. On lance
`| stats count by index` sur `_audit`.

**Résultat observé.** L'utilisateur **peut lire** `_audit` (count >
0). La chaîne `-_audit` est stockée littéralement, traitée comme
nom d'index (qui n'existe pas), **et n'exclut rien**. Le même
résultat est obtenu avec `!_audit`.

**Conséquence pour la gouvernance.** L'exclusion **doit** passer par
`srchIndexesDisallowed`. Toute documentation interne mentionnant la
syntaxe `-<index>` ou `!<index>` est erronée et à corriger.

### F-RBAC-06 — `srchFilter` se combine en OR

**Hypothèse.** Un lecteur intuitif pourrait s'attendre à ce que
`srchFilter` se combine en AND entre rôles d'un utilisateur (chaque
filtre restrictif s'ajoute).

**Test mené.** Soit un utilisateur portant un rôle avec
`srchFilter="region=eu"` et un autre avec `srchFilter="*"` (ou champ
vide). Il lance `| stats count by region`.

**Résultat observé.** L'utilisateur voit **toutes** les régions. La
combinaison multi-rôles est en **OR** : `region=eu OR *` = tout.

**Conséquence pour la gouvernance.** **Bannir `srchFilter=*`** dans
tout rôle métier. Laisser le champ vide à la place — c'est
sémantiquement équivalent côté permissions mais évite l'annulation
accidentelle des filtres restrictifs des autres rôles.

### F-RBAC-07 — ACL d'app : write sans read = invisible

**Hypothèse documentée.** La doc Splunk sur la gestion des
permissions de knowledge objects décrit l'ACL `perms.read=role_A` et
`perms.write=role_B` comme accordant lecture à `role_A` **et**
écriture à `role_B` (le « read OU write »).

**Test mené.** On crée une saved search dans une app avec
`perms.read=role_consultatif` et `perms.write=role_owner` (sans
inclusion de `role_owner` dans `perms.read`). Un utilisateur portant
uniquement `role_owner` ouvre l'app.

**Résultat observé.** La saved search est **invisible (404)** pour
l'utilisateur `role_owner` — il ne la voit pas dans la liste des
saved searches de l'app, et l'URL directe renvoie 404.

**Conséquence pour la gouvernance.** **Toujours coupler read +
read/write** dans les ACL : `perms.read=role_A;role_B`,
`perms.write=role_B`. Les atomiques `app_<prod>` doivent venir en
paires `app_<prod>_read` et `app_<prod>_rw` ; un composite qui doit
écrire importe les deux.

### F-RBAC-08 — Pièges REST opérationnels majeurs

**Trois pièges** observés empiriquement sur l'API REST 9.4.6 qui
peuvent **casser silencieusement** la plateforme.

**Piège 1 — POST sur un rôle existant = SET destructif.** Un POST
partiel sur `/services/authorization/roles/<role>` qui ne mentionne
que `capabilities=cap1` **remplace toute** la liste de capabilities
du rôle. Aucun warning. Le pattern obligatoire est **GET → merge en
local → POST complet** avec la liste totale des champs.

**Piège 2 — DELETE d'un built-in autorisé sans confirmation.**
`DELETE /services/authorization/roles/user` renvoie HTTP 200. La
conséquence cascade : `power.importRoles` est réinitialisé à `[]`,
`admin` perd l'héritage de `search`, toute la plateforme refuse les
jobs. Restauration manuelle obligatoire à partir d'un snapshot.

**Piège 3 — DELETE d'un rôle utilisé supprime les users en cascade.**
Splunk refuse les utilisateurs sans rôle. Donc supprimer le dernier
rôle d'un utilisateur supprime **l'utilisateur** et ses ressources
privées (saved searches, dashboards privés). Aucun warning, aucune
confirmation.

**Conséquence pour la gouvernance.**

- Snapshot REST complet **avant toute modification** structurelle.
- Pattern GET → merge → POST complet **obligatoire** pour les
  modifications de rôle.
- Migration de rôle **en deux temps** : (1) créer le nouveau rôle,
  (2) réassigner les users, (3) seulement ensuite supprimer
  l'ancien.

## Famille SAML

### F-SAML-01 — `defaultRolesIfMissing` est un fallback, pas un plancher

**Hypothèse.** Le paramètre `defaultRolesIfMissing` de
`authentication.conf` pourrait sembler un « rôle plancher » cumulé
avec les rôles mappés.

**Test et observation.** `defaultRolesIfMissing` est strictement un
**fallback** — il s'applique seulement quand l'IdP n'émet aucun
groupe mappé. Un utilisateur avec au moins un groupe mappé ne reçoit
**que** les rôles mappés, sans cumul du fallback.

**Conséquence pour la gouvernance.** Pour un rôle plancher
(`role_floor`) attribué à tous les utilisateurs authentifiés, la
voie est de mapper explicitement un groupe IdP « all-users » à
`role_floor` via `roleMap_`, **pas** d'utiliser
`defaultRolesIfMissing`.

**Garde-fou critique.** **Ne jamais** mettre `admin` dans
`defaultRolesIfMissing`. Splunk utilise temporairement `admin` pour
traiter l'information de groupe SAML — un fallback à `admin` ouvre
la porte à une **escalade accidentelle**. Toujours `role_no_access`
ou un rôle minimal équivalent.

### F-SAML-02 — Auto-mapping et homonymie de groupes

**Observation.** L'auto-mapping (`enableAutoMappedRoles=true`)
déclenche l'attribution d'un rôle Splunk si l'IdP émet un groupe de
**nom exactement égal** au rôle (en minuscules). C'est pratique pour
le gros volume mais ouvre un risque d'**homonymie accidentelle** :
si un groupe d'annuaire existe avec un nom qui correspond à un rôle
sensible (`admin`, `admin_ops`), l'utilisateur peut se voir attribuer
ce rôle.

**Conséquence pour la gouvernance.** **Ne jamais** auto-mapper les
rôles administratifs. Toujours combiner :

```ini
[saml]
enableAutoMappedRoles = true
excludedAutoMappedRoles = admin;admin_iam;admin_ops
roleMap_<authSettings> = admin_iam:splunk_admin_iam;admin_ops:splunk_admin_ops;role_floor:splunk_all_users
```

### F-SAML-03 — Wildcard sur les groupes : impossible

**Observation.** Splunk 9.4 traite la valeur du `roleMap_*` **comme
chaîne littérale**. Pas de wildcard côté groupe : `role_floor:*`
n'attribue `role_floor` à personne.

**Conséquence.** Le rôle plancher passe nécessairement par un
**groupe IdP « all-users »** explicite mappé à `role_floor`.

## Famille WLM

### F-WLM-01 — Chaque catégorie exige un pool default

**Hypothèse documentée.** La documentation Splunk décrit
`default_category_pool=1` comme une option pour désigner le pool par
défaut d'une catégorie. Un lecteur attentif comprendrait qu'il en faut
au moins un par catégorie utilisée.

**Test mené.** On configure une catégorie `search` avec ses cinq
pools métier (`admin`, `scheduled`, `ad_hoc`, `bulk`, `accel`), un
seul `default_category_pool=1` sur `ad_hoc`. Les catégories `ingest`
et `misc` existent mais sans pool default. On active WLM via
`workload-management-status enabled=1`.

**Résultat observé.** L'activation **échoue silencieusement**. Le
toggle reste à `0`. `splunkd.log` montre une erreur d'initialisation
qui pointe vers l'absence de `default_category_pool=1` sur les
catégories `ingest` et `misc`.

**Test complémentaire.** Ajout de `ingest_default` et `misc_default`
avec `default_category_pool=1` dans `ingest` et `misc`. L'activation
réussit.

**Conséquence pour la gouvernance.** La conception nominale doit
prévoir **sept pools** :

- cinq pools métier dans `search` (`admin`, `scheduled`, `ad_hoc`,
  `bulk`, `accel`) ;
- un pool default dans `ingest` (`ingest_default`) ;
- un pool default dans `misc` (`misc_default`).

Les deux pools default des catégories non métier reçoivent un poids
minimal (1 % chacun en `cpu_weight` et `mem_weight`) ; ils existent
seulement pour permettre l'activation.

### F-WLM-02 — Placement implicite, pas `action=workload_pool`

**Hypothèse.** Une lecture rapide de la doc pourrait suggérer une
`action = workload_pool` pour le placement (par analogie avec
`action = abort`, `action = move`).

**Test mené.** Une `workload_rule` avec `action = workload_pool` et
`workload_pool = scheduled`.

**Résultat observé.** splunkd rejette : « invalid action
`workload_pool` ». Les actions valides sont `move`, `abort`,
`alert`, `filter`, `queue`.

**Comportement réel.** Le placement est **implicite** : la simple
présence de la clé `workload_pool = <pool>` dans une `[workload_rule:*]`
qui matche **sans** clef `action=` suffit à router la recherche dans
le pool désigné.

**Conséquence pour la gouvernance.** Toute documentation interne
mentionnant `action=workload_pool` est à corriger. Le placement est
implicite.

### F-WLM-03 — `runtime>` obligatoire pour `abort/move/alert`

**Observation.** Les actions de monitoring (`abort`, `move`, `alert`)
sont évaluées **en cours d'exécution**, toutes les dix secondes. Pour
qu'une `workload_rule` les déclenche, son prédicat **doit** inclure
une borne `runtime>` (par exemple `runtime>1s`, `runtime>1m`). À
défaut, splunkd refuse la règle à l'activation avec une erreur
explicite.

**Conséquence pour la gouvernance.** Toute règle de monitoring
porte une borne `runtime>` minimale, même symbolique (`runtime>1s`
suffit pour activer le mécanisme). Les règles de **placement seul**
n'en ont pas besoin.

### F-WLM-04 — `action = display_message` n'existe pas

**Hypothèse documentée.** La documentation Splunk 9.4 sur les
workload rules mentionne `display_message` comme valeur d'action
permettant un mode « notification sans contrainte » — la recherche
tourne, un message est affiché.

**Test mené.** Une `workload_rule` avec `action = display_message`.

**Résultat observé.** splunkd **rejette** la règle : « Valid actions
are `move`, `abort`, `alert`, `filter`, and `queue` ». La valeur
`display_message` **n'existe pas** en 9.4.6.

**Équivalent fonctionnel.** `action = alert`. La recherche continue,
un événement est écrit dans `_audit`, un message structuré apparaît
dans le job inspector. C'est l'équivalent natif d'un **mode
monitor-only par règle**.

**Conséquence pour la gouvernance.** **Tout** déploiement
monitor-only WLM utilise `action = alert`. Toute documentation
interne mentionnant `display_message` est à corriger. Ce finding
seul économise plusieurs jours de débogage à une équipe qui
tenterait le déploiement sur la foi de la doc.

### F-WLM-05 — `[workload_rules_order]` n'accepte que les `[workload_rule:*]`

**Observation.** L'ordre d'évaluation est défini dans
`[workload_rules_order]` par une clé `rules = rule_A, rule_B, …`.
Tenter d'y inscrire une `[search_filter_rule:*]` (admission rule)
provoque un HTTP 404 à l'activation. Les admission rules sont
évaluées **en parallèle**, sans ordre.

**Conséquence.** L'ordre concerne les workload rules uniquement. Les
admission rules ne s'ordonnent pas — il suffit qu'une seule matche
`filter` pour bloquer.

### F-WLM-06 — `user_message` des admission rules : contraintes de syntaxe

**Observation.** Le champ `user_message` d'une `search_filter_rule`
(le message renvoyé au client quand l'action est `filter`) porte
plusieurs contraintes empiriquement observées en 9.4.6 : longueur
maximale d'environ 140 caractères, jeu de caractères restreint
(alphanumériques, espaces, virgule, deux-points, point-virgule,
point, underscore, tiret, apostrophe, guillemet), **pas de
parenthèses**. Une chaîne avec parenthèses fait rejeter la règle.

**Conséquence.** Rédiger les `user_message` en phrases simples sans
parenthèses. Utiliser deux-points ou tirets pour structurer si
besoin.

### F-WLM-07 — Hot-reload côté search head, restart côté indexer

**Observation.** Sur un search head, modifier `workload_pools.conf`
ou `workload_rules.conf` puis appeler
`POST /services/workloads/config/_reload` recharge la configuration
sans interruption.

Sur un peer indexer en cluster, la propagation passe par le **cluster
master** (`splunk apply cluster-bundle`) qui **redémarre les peers**
(rolling restart). Pas de hot-reload côté indexer pour les bundles
WLM.

**Conséquence pour la gouvernance.** Sur un search head, le cycle
d'itération est rapide (modification + reload). Sur un cluster
d'indexers, chaque modification de bundle WLM implique un rolling
restart — à planifier hors heures critiques.

### F-WLM-08 — Restart Splunkd doit être en root direct

**Observation.** Au premier déploiement de WLM, un restart de
Splunkd est nécessaire pour qu'il attache ses processus aux cgroups.
Sur une installation systemd, le restart **doit** être en root direct
(`systemctl restart Splunkd`), **pas** via `runuser -u splunk --
splunk restart` qui échoue silencieusement avec « Access denied » sur
les services systemd-managed.

**Conséquence.** Toute procédure de déploiement WLM doit l'expliciter.
Les outils d'automatisation doivent utiliser `systemctl` côté service,
pas le wrapper `splunk` côté binaire.

## Famille ACL d'app

### F-ACL-01 — Héritage actif des ACL d'objets via `importRoles`

**Observation.** Une ACL d'objet posée sur un rôle parent
(`perms.read=role_parent`) est **héritée** par les rôles enfants qui
importent ce parent via `importRoles`. La couche ACL d'objet est
évaluée sur l'ensemble effectif des rôles, **rôles importés inclus**.

**Conséquence pour la gouvernance.** Les ACL d'apps et de knowledge
objects peuvent (et doivent) référencer les **atomiques `app_*`**.
Les composites qui les importent récupèrent automatiquement les
accès. C'est ce qui rend le pattern atomiques/composites cohérent
jusque dans la couche ACL.

## Tableau récapitulatif des findings

| Code | Famille | Comportement réel 9.4.6 |
| --- | --- | --- |
| F-RBAC-01 | RBAC | Capability héritée non révocable, `=disabled` est un no-op silencieux |
| F-RBAC-02 | RBAC | Quotas non hérités au sens enforcement, `max()` multi-rôles |
| F-RBAC-03 | RBAC | `srchIndexesAllowed=*` ne couvre pas les internes `_*` |
| F-RBAC-04 | RBAC | `srchIndexesDisallowed` prévaut, s'hérite, most-restrictive multi-rôles |
| F-RBAC-05 | RBAC | Syntaxe `-_audit` / `!_audit` invalide (no-op) |
| F-RBAC-06 | RBAC | `srchFilter` se combine en OR multi-rôles, `*` annule tout |
| F-RBAC-07 | RBAC | ACL d'app `write` sans `read` = invisible (404) |
| F-RBAC-08 | RBAC | POST = SET destructif ; DELETE built-in casse `admin` ; DELETE rôle utilisé supprime users |
| F-SAML-01 | SAML | `defaultRolesIfMissing` est un fallback, pas un plancher ; jamais `admin` |
| F-SAML-02 | SAML | Auto-mapping risque d'homonymie ; `excludedAutoMappedRoles` obligatoire pour `admin_*` |
| F-SAML-03 | SAML | Pas de wildcard côté groupe ; rôle plancher via groupe « all-users » explicite |
| F-WLM-01 | WLM | Chaque catégorie (`search`, `ingest`, `misc`) exige un `default_category_pool=1` |
| F-WLM-02 | WLM | Placement implicite via `workload_pool=`, pas `action=workload_pool` |
| F-WLM-03 | WLM | `runtime>` obligatoire pour les actions de monitoring (`abort`/`move`/`alert`) |
| F-WLM-04 | WLM | `action=display_message` n'existe pas ; utiliser `action=alert` |
| F-WLM-05 | WLM | `[workload_rules_order]` n'accepte que les `[workload_rule:*]` |
| F-WLM-06 | WLM | `user_message` : ~140 chars, pas de parenthèses |
| F-WLM-07 | WLM | Hot-reload côté SH ; restart côté indexer via cluster-bundle |
| F-WLM-08 | WLM | Restart Splunkd en root direct (`systemctl`), pas via `runuser` |
| F-ACL-01 | ACL | Héritage actif des ACL d'objets via `importRoles` |

## Comment utiliser ces findings

Ces findings sont **opposables**. Un praticien Splunk qui rencontre
une décision technique en désaccord avec un de ces points peut citer
le finding par son code et son test, et déclencher une vérification
sur le binaire 9.4.6 réel.

C'est la valeur principale du chapitre : aucun de ces comportements
ne se déduit d'une lecture pure de la documentation officielle. Ils
ne se découvrent que par maquette.

## Sources

- [Splunk Securing 9.4 — Roles and capabilities](https://help.splunk.com/en/splunk-enterprise/administer/secure-splunk-enterprise/9.4/define-roles-on-the-splunk-platform/about-defining-roles-with-capabilities)
- [Splunk Admin 9.4 — authorize.conf](https://help.splunk.com/en/data-management/splunk-enterprise-admin-manual/9.4/configuration-file-reference/9.4.5-configuration-file-reference/authorize.conf)
- [Splunk Admin 9.4 — authentication.conf](https://help.splunk.com/en/data-management/splunk-enterprise-admin-manual/9.4/configuration-file-reference/9.4.5-configuration-file-reference/authentication.conf)
- [Splunk Workload Management 9.4 — Configure workload rules](https://help.splunk.com/en/splunk-enterprise/administer/manage-workloads/9.4/configure-workload-management/configure-workload-rules)
- [Splunk Workload Management 9.4 — Configure admission rules](https://help.splunk.com/en/splunk-enterprise/administer/manage-workloads/9.4/configure-workload-management/configure-admission-rules-to-prefilter-searches)
