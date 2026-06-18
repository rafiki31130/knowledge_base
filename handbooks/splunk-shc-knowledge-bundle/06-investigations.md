# Chapitre 6 — Investigations : boîte à outils

> Ce chapitre est la **référence** consultée face à un incident. Quatre tableaux exhaustifs — CLI, REST, filtres `splunkd.log`, SPL `index=_internal` — listent les commandes et requêtes utiles, avec leur source documentaire Splunk 9.4 quand elle existe et la mention « observé empiriquement » quand le composant ou l'endpoint n'a pas de page de référence dédiée. Le chapitre se termine par trois combos types (« santé deployer en 3 commandes », « hash divergent en 4 SPL », « peer perdu en 2 REST ») qui condensent les enchaînements les plus fréquents.

## Rappels rapides

- Les commandes citées ici sont **toutes** celles utilisées dans l'arbre de diagnostic du chap. 05. Quand le chap. 05 dit « cf. chap. 06 § N », c'est ici.
- Splunk ne documente individuellement, parmi les composants `splunkd.log` pertinents, que `DistributedBundleReplicationManager`. Les autres composants utilisés en diag sont marqués « observé empiriquement — non documenté Splunk ». À grepper sur un `splunkd.log` 9.4 réel pour confirmer leur présence dans votre version.
- Toutes les commandes REST utilisent le port mgmt par défaut `8089` et l'authentification basic. En production, préférer un token Splunk (cf. doc Splunk).
- Les SPL `index=_internal` listées sont prêtes à coller — time range explicite, anonymisation des hosts cibles.

## 1. CLI investigateur

Le tableau ci-dessous est à reproduire dans un cheat-sheet local. Chaque commande est précédée du nœud d'exécution (deployer / captain / membre SHC / SH / CM / peer indexer).

| Commande | Description | Source Splunk 9.4 |
| --- | --- | --- |
| `splunk apply shcluster-bundle -target https://captain01.example.com:8089 -auth admin:<password>` (sur deployer) | Pousse le configuration bundle SHC du deployer vers le captain. Options `-action stage|send`, `-preserve-lookups`, `-push-default-app-conf`. | [PropagateSHCconfigurationchanges](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/PropagateSHCconfigurationchanges) |
| `splunk show shcluster-bundle-status -auth admin:<password>` (sur deployer) | État du dernier push de bundle depuis le deployer vers le captain. | [ViewSHCstatus](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus) |
| `splunk list shcluster-bundle-status -auth admin:<password>` (sur captain) | État de propagation aux membres SHC : `bundle_id` par membre. | [ViewSHCstatus](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus) |
| `splunk show shcluster-status -auth admin:<password>` (sur n'importe quel membre) | État global du SHC : captain courant, membres et leurs états, ports replication. | [ViewSHCstatus](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus) |
| `splunk list shcluster-member-info -auth admin:<password>` (sur n'importe quel membre) | Détails du membre courant : GUID, mode, kvstore state. | [ViewSHCstatus](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus) |
| `splunk rolling-restart shcluster-members -auth admin:<password>` (sur captain) | Restart roulant des membres SHC, utile après un apply avec changement nécessitant restart. | [ViewSHCstatus](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus) |
| `splunk apply cluster-bundle --answer-yes -auth admin:<password>` (sur CM) | Pousse le configuration bundle indexer cluster du CM vers les peers indexer. | [Updatepeerconfigurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Updatepeerconfigurations) |
| `splunk validate cluster-bundle --check-restart -auth admin:<password>` (sur CM) | Valide le configuration bundle indexer cluster avant push, prédit les peers qui demanderont restart. | [Updatepeerconfigurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Updatepeerconfigurations) |
| `splunk show cluster-bundle-status -auth admin:<password>` (sur CM) | État de propagation du bundle indexer cluster aux peers. | [Updatepeerconfigurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Updatepeerconfigurations) |
| `splunk rolling-restart cluster-peers -auth admin:<password>` (sur CM) | Restart roulant des peers indexer cluster après un cluster-bundle qui requiert restart. | [Restartthecluster](https://docs.splunk.com/Documentation/Splunk/9.4.2/Indexer/Restartthecluster) |
| `splunk list distributed-peer -auth admin:<password>` (sur SH) | Liste les peers de search distribuée connus du SH et leur état. La forme exacte de la sous-commande peut varier ; `splunk help distributed` la confirme sur l'instance. | [Configuredistributedsearch](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Configuredistributedsearch) |
| `splunk show distributed-peers -auth admin:<password>` (sur SH) | Alternative à la précédente — affichage souvent plus lisible. Inclut le hash de bundle SH-déclaré quand pertinent. | [Configuredistributedsearch](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Configuredistributedsearch) |
| `splunk btool check` (sur n'importe quel nœud) | Vérifie la cohérence des `.conf` chargés (utile en diag A3 : validation refusée). | Observé empiriquement — documenté indirectement dans le Splunk Troubleshooting Manual. |
| `splunk btool clustering list` (sur SH / peer / CM) | Affiche la stanza `[clustering]` effective après merge des `.conf`. Utile en diag D3 (pass4SymmKey divergent). | Observé empiriquement — documenté indirectement. |
| `splunk status` (sur n'importe quel nœud) | État du processus splunkd. Utile en diag A1 (deployer down). | [WhatSplunklogsaboutitself](https://docs.splunk.com/Documentation/Splunk/9.4.2/Troubleshooting/WhatSplunklogsaboutitself) |

> Note : `splunk show shcluster-bundle-status` (deployer-side) vs `splunk list shcluster-bundle-status` (captain-side) — `show` est l'état du **dernier push effectué**, `list` est l'état de **propagation aux membres**. Les deux complémentaires en diag.

## 2. REST investigateur

Les endpoints REST ci-dessous sont à interroger via `curl -k -u admin:<password> https://<host>:8089/...`. Ajouter `?output_mode=json` pour une sortie exploitable en script.

| Endpoint | Méthode | Description | Source Splunk 9.4 |
| --- | --- | --- | --- |
| `/services/shcluster/captain/info` | GET | Info du captain : durée mandat, ID, état du SHC. À interroger sur le captain (ou sur un membre — la requête est redirigée). | [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster) |
| `/services/shcluster/captain/members` | GET | Liste des membres SHC vus par le captain, avec leur état et leur `bundle_id` courant. | [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster) |
| `/services/shcluster/member/info` | GET | Info du membre local — à interroger sur chaque membre individuellement pour comparer. | [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster) |
| `/services/cluster/manager/info` | GET | État du cluster manager (indexer cluster, terminologie 9.4). | [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster) |
| `/services/cluster/manager/peers` | GET | Liste des peers indexer cluster, état bucket, état de réplication. | [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster) |
| `/services/cluster/manager/control/default/apply` | POST | Déclenche l'apply du configuration bundle indexer cluster (équivalent CLI `splunk apply cluster-bundle`). | [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster) |
| `/services/cluster/config` | GET | Configuration cluster manager exposée. Utile pour vérifier `replication_factor`, `search_factor`. | [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster) |
| `/services/search/distributed/peers` | GET | Sur SH : peers de search distribuée et leur état (incl. hash bundle SH-déclaré quand exposé). | [RESTprolog](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTprolog) |
| `/services/search/distributed/bundle/replication/config` | GET | Configuration courante de la réplication knowledge bundle SH→peers (paramètres effectifs après merge). | [Troubleshootknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Troubleshootknowledgebundlereplication) |
| `/services/search/distributed/bundle/replication/cycles` | GET | Historique des cycles de réplication bundle SH→peers : timestamp, peers cibles, état, taille. C'est l'endpoint principal pour caractériser un échec récent. | [Troubleshootknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Troubleshootknowledgebundlereplication) |

> Note : certains endpoints `/services/admin/*` peuvent exister et retourner des informations utiles, mais Splunk demande explicitement de **ne pas les documenter publiquement** ni les automatiser. Ils sont traités en chap. 07 comme un piège (tentation à éviter) et ne figurent pas dans ce tableau.

### Exemples concrets

```bash
# Sur le SH : etat de tous les peers de search distribuée (JSON)
curl -k -u admin:<password> \
  "https://shcMember01.example.com:8089/services/search/distributed/peers?output_mode=json" \
  | jq '.entry[] | {name, "status": .content.status, "build": .content.build}'

# Sur le captain : etat de propagation du bundle SHC aux membres
curl -k -u admin:<password> \
  "https://captain01.example.com:8089/services/shcluster/captain/members?output_mode=json" \
  | jq '.entry[] | {name, "status": .content.status, "bundle_id": .content.bundle_id}'

# Sur le SH : historique des cycles de replication bundle SH peers
curl -k -u admin:<password> \
  "https://shcMember01.example.com:8089/services/search/distributed/bundle/replication/cycles?output_mode=json"
```

## 3. Filtres `splunkd.log`

Le tableau ci-dessous liste les composants à grepper dans `splunkd.log` (indexé `index=_internal sourcetype=splunkd`). Splunk ne documente individuellement que `DistributedBundleReplicationManager` parmi ceux pertinents pour le bundle ; les autres sont marqués « observé empiriquement ».

| Filtre (composant) | Quoi surveiller | Source / statut |
| --- | --- | --- |
| `component=DistributedBundleReplicationManager` | Cycles de réplication bundle SH → peers, erreurs de taille, timeouts, hash divergence côté SH. C'est **le** composant principal documenté. | [Troubleshootknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Troubleshootknowledgebundlereplication) |
| `component=ApplyBundleHandler` (à confirmer par grep) | Réception côté peer d'un apply cluster-bundle (indexer cluster). | Observé empiriquement — *non documenté Splunk* individuellement |
| `component=ConfReplicationThread` (à confirmer par grep) | Conf replication interne SHC (post-apply deployer). Cycles, objets push/pull. | Observé empiriquement — *non documenté Splunk* individuellement |
| `component=ConfReplication*` (préfixe — à confirmer par grep) | Variantes du composant ci-dessus selon version mineure 9.x. | Observé empiriquement |
| `component=CMMaster` | Cluster manager indexer (terminologie legacy `master` encore présente dans les logs 9.4 pour rétrocompatibilité). | Observé empiriquement — *non documenté Splunk* individuellement |
| `component=CMPeer` | Peer indexer cluster (terminologie legacy `peer`). | Observé empiriquement — *non documenté Splunk* individuellement |
| `component=SHCMaster` (variantes selon version) | Coordination SHC interne, élection captain. | Observé empiriquement |
| `component=SHCSchedulerDelegator` (à confirmer par grep) | Décision côté SHC d'exécuter une saved search clusterisée sur le captain. | Observé empiriquement — *non documenté Splunk* individuellement |
| `log_level=ERROR OR log_level=WARN` + `bundle` dans message | Filet large pour erreurs bundle non typées. Premier réflexe en triage. | Pratique standard |

### Exemples de lignes type

```text
2026-06-18 10:00:00.123 +0000 INFO  DistributedBundleReplicationManager - cycle starting peers=3 bundle_size_bytes=234567890
2026-06-18 10:00:01.456 +0000 INFO  DistributedBundleReplicationManager - peer=peer01 push complete bytes=234567890 elapsed_ms=1234
2026-06-18 10:00:02.789 +0000 WARN  DistributedBundleReplicationManager - peer=peer02 push failed reason=timeout elapsed_ms=60000
2026-06-18 10:00:02.999 +0000 ERROR DistributedBundleReplicationManager - cycle complete with errors success=2 failed=1
```

```text
2026-06-18 10:01:00.123 +0000 INFO  ConfReplicationThread - conf replication cycle starting members=3
2026-06-18 10:01:00.456 +0000 INFO  ConfReplicationThread - pushed 12 objects to shcMember02
2026-06-18 10:01:00.789 +0000 INFO  ConfReplicationThread - cycle complete duration_ms=666
```

### Recommandations de grep

```bash
# Sur le SH : derniers cycles de replication bundle, erreurs en evidence
grep -E "DistributedBundleReplicationManager.*(WARN|ERROR)" \
  $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -50

# Sur le captain : derniers cycles de conf replication interne SHC
grep "ConfReplicationThread" $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -50

# Sur le peer indexer : reception apply cluster-bundle
grep "ApplyBundleHandler" $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -50
```

## 4. SPL `index=_internal` — recherches prêtes à coller

Cinq recherches consolidées, time range explicite, anonymisation des hosts dans les exemples (toutes utilisent `host` en sortie pour repérer le nœud, sans préfixage en input).

### 4.1. Erreurs de réplication knowledge bundle SH → peers sur 24h

```spl
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager log_level=ERROR earliest=-24h@h latest=now
| stats count by host, message
| sort -count
```

**Objectif.** Identifier les SH qui produisent des erreurs et les messages dominants. Permet de prioriser le nœud à investiguer en premier. Source : composant Splunk documenté.

### 4.2. Activité bundle récente, par SH

```spl
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager "bundle" earliest=-1h@m latest=now
| stats latest(_time) as last_seen by host, message
| sort -last_seen
```

**Objectif.** Voir si la réplication tourne actuellement (le `last_seen` doit être récent) et si elle produit des messages anormaux. Source : composant Splunk documenté.

### 4.3. Trace des `apply shcluster-bundle` sur 7 jours

```spl
index=_internal sourcetype=splunkd "shcluster-bundle" earliest=-7d@d latest=now
| stats count by host, log_level
| sort host
```

**Objectif.** Historique des apply SHC bundle. Le mot-clé est fiable (c'est le nom de la sous-commande). Source : mot-clé recherché — fiable car nom de commande.

### 4.4. Erreurs apply cluster-bundle (indexer cluster) sur 7 jours

```spl
index=_internal sourcetype=splunkd "cluster-bundle" (log_level=WARN OR log_level=ERROR) earliest=-7d@d latest=now
| stats count by host, message
| sort -count
```

**Objectif.** Erreurs récentes côté CM ou peers sur les apply cluster-bundle. Source : mot-clé recherché.

### 4.5. Appels REST shcluster bundle reçus, vue access log

```spl
index=_internal sourcetype=splunkd_access uri_path="*shcluster*bundle*" earliest=-1h@m latest=now
| stats count by host, uri_path, status
| sort -count
```

**Objectif.** Voir qui appelle quels endpoints shcluster bundle et avec quel code de retour. Utile pour identifier les appels d'un script de supervision ou tracer un push qui n'a pas abouti. Source : sourcetype Splunk standard.

### 4.6. (Bonus) Hash convergence — métrique de routine

Cette SPL n'est pas dans le tableau §7.4 de la spec mais sa logique est mentionnée au chap. 05 § 12 (métriques de routine). Elle nécessite un croisement entre l'état SH-déclaré et l'état peer-effectif que Splunk ne fournit pas en un endpoint unique ; en pratique, l'admin l'implémente en saved search programmée alimentant un summary index, en agrégeant `splunkd.log` de chaque peer (entrée `received bundle hash=...`). Pattern :

```spl
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager "received" earliest=-1h@m latest=now
| rex "hash=(?<hash>[a-f0-9]+)"
| stats values(hash) as hashes count by host
| where mvcount(hashes) > 1
```

**Interprétation.** Tout `host` avec `mvcount(hashes) > 1` sur une fenêtre courte a vu plusieurs hashes — indicateur de cycles fréquents (normal en activité haute) ou de divergence (à corréler avec le hash courant SH).

## 5. Combos types

### 5.1. Santé deployer en 3 commandes

À jouer face au symptôme « l'apply shcluster-bundle semble ne rien faire ».

```bash
# 1. Etat du processus deployer
splunk status

# 2. Dernier push effectue depuis le deployer
splunk show shcluster-bundle-status -auth admin:<password>

# 3. Etat global du SHC vu d'un membre (captain stable ?)
splunk show shcluster-status -auth admin:<password>
```

Lecture : (1) doit montrer splunkd up. (2) doit montrer `last_apply_time` récent et un `bundle_id` cohérent. (3) doit montrer un captain stable et tous les membres up.

### 5.2. Hash divergent en 4 SPL

À jouer face au symptôme « deux SH membres voient les peers dans des états différents ».

```spl
# 1. Quels SH produisent activement des cycles ?
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager "cycle" earliest=-1h@m latest=now
| stats latest(_time) as last_cycle by host
| sort -last_cycle

# 2. Quels cycles ont echoue recemment ?
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager log_level=ERROR earliest=-1h@m latest=now
| stats count by host, message

# 3. Quels peers sont en defaut ?
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager "peer=" earliest=-1h@m latest=now
| rex "peer=(?<peer>[\w\.-]+)"
| stats count by host, peer, log_level

# 4. Vue access log : appels REST recents vers les endpoints de bundle
index=_internal sourcetype=splunkd_access uri_path="*distributed*bundle*" earliest=-1h@m latest=now
| stats count by host, uri_path, status
```

Lecture : (1) caractérise l'activité par SH. (2) liste les erreurs récentes. (3) isole les peers fautifs. (4) confirme côté HTTP que les appels arrivent et avec quel code.

### 5.3. Peer perdu en 2 REST

À jouer face au symptôme « un peer en particulier ne reçoit plus le bundle ».

```bash
# 1. Etat du peer cote SH
curl -k -u admin:<password> \
  "https://shcMember01.example.com:8089/services/search/distributed/peers?output_mode=json" \
  | jq '.entry[] | select(.name | contains("peer02")) | {name, "status": .content.status, "build": .content.build}'

# 2. Etat du peer cote CM
curl -k -u admin:<password> \
  "https://cm01.example.com:8089/services/cluster/manager/peers?output_mode=json" \
  | jq '.entry[] | select(.name | contains("peer02")) | {name, "status": .content.status}'
```

Lecture : (1) état vu du SH (down ? quarantined ?). (2) état vu du CM (enrôlé ? actif ?). Une divergence entre les deux vues (peer up côté CM, down côté SH) oriente vers un problème de routage / `serverList` côté SH.

## 6. Notes générales d'usage

- **Toujours commencer par un échantillon temporel resserré** (`earliest=-1h@m`) avant d'élargir. La masse de `_internal` est suffisante pour que des recherches sur 7 jours soient coûteuses.
- **Anonymiser les outputs** quand on copie un résultat dans une demande de support ou un mail. Les noms d'hôte réels n'ont pas leur place hors du périmètre opérationnel interne.
- **Ne pas combiner les recherches investigation et alerting** dans la même saved search. Les recherches investigation sont ad hoc, fenêtre courte. Les alertes sont programmées, fenêtre fixée, seuils.
- **Sondage de cohérence** : avant de croire à un bug Splunk, vérifier deux à trois éléments cohérents (CLI + REST + log) sur le même symptôme. Une divergence entre sources de vérité interne au nœud est elle-même un symptôme.

## Sources

- [Splunk DistSearch 9.4 — Propagate SHC configuration changes](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/PropagateSHCconfigurationchanges)
- [Splunk DistSearch 9.4 — View SHC status](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus)
- [Splunk DistSearch 9.4 — Troubleshoot knowledge bundle replication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Troubleshootknowledgebundlereplication)
- [Splunk DistSearch 9.4 — Configure distributed search](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Configuredistributedsearch)
- [Splunk Indexer 9.4 — Update peer configurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Updatepeerconfigurations)
- [Splunk Indexer 9.4 — Configuration bundle issues](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Configurationbundleissues)
- [Splunk Indexer 9.4 — Restart the cluster](https://docs.splunk.com/Documentation/Splunk/9.4.2/Indexer/Restartthecluster)
- [Splunk REST API 9.4 — Cluster endpoints](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster)
- [Splunk REST API 9.4 — Prolog](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTprolog)
- [Splunk Troubleshooting 9.4 — What Splunk logs about itself](https://docs.splunk.com/Documentation/Splunk/9.4.2/Troubleshooting/WhatSplunklogsaboutitself)
- [Splunk Admin 9.4 — distsearch.conf](https://docs.splunk.com/Documentation/Splunk/9.4.0/Admin/Distsearchconf)
- [Splunk Admin 9.4 — server.conf](https://docs.splunk.com/Documentation/Splunk/9.4.2/Admin/Serverconf)
