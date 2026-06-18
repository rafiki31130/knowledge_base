# Chapitre 99 — Cheatsheet diag rapide

> Une page imprimable. Le bon ordre des premières commandes à taper face à un incident bundle, sans réfléchir. Trois sections triage (SHC bundle, knowledge bundle de search, indexer cluster bundle), une section logs, une section SPL. Les commandes citées sont détaillées au chap. 06.

## Rappels rapides

- Avant tout : **identifier de quel bundle on parle** (cf. chap. 00 § 2). Trois mécaniques portent le mot.
- Toutes les commandes ci-dessous utilisent `-auth admin:<password>` ; en production, préférer un token.
- Si le diag rapide ne tranche pas en 5 minutes, passer au chap. 05 (arbre complet).

## 1. Triage en 5 commandes — configuration bundle SHC

À jouer face à « `splunk apply shcluster-bundle` semble ne rien faire » ou « un membre SHC n'a pas la dernière app ».

```bash
# Sur le deployer
splunk status
splunk show shcluster-bundle-status -auth admin:<password>

# Sur n'importe quel membre SHC (redirige vers captain)
splunk show shcluster-status -auth admin:<password>
splunk list shcluster-bundle-status -auth admin:<password>
splunk list shcluster-member-info -auth admin:<password>
```

**Lecture rapide.**

1. `splunk status` (deployer) : splunkd up ?
2. `splunk show shcluster-bundle-status` (deployer) : dernier push réussi ? `last_apply_time` récent ?
3. `splunk show shcluster-status` (membre) : captain stable ? tous les membres up ? RF respecté ?
4. `splunk list shcluster-bundle-status` (captain) : `bundle_id` cohérent entre tous les membres ?
5. `splunk list shcluster-member-info` (membre) : GUID, état kvstore, mode.

**Décision.** Si 1-3 OK et 4 divergent : chap. 05 branche B. Si 1 KO : chap. 05 branche A1. Si 3 montre captain absent : chap. 05 branche A2.

## 2. Triage en 5 commandes — knowledge bundle de search

À jouer face à « recherche bloquée en attente bundle » ou « un peer ne voit pas la dernière lookup ».

```bash
# Sur le SH (ou membre SHC en tant que SH)
splunk show distributed-peers -auth admin:<password>
splunk list distributed-peer -auth admin:<password>

# REST : etat detaille des peers
curl -k -u admin:<password> \
  "https://shcMember01.example.com:8089/services/search/distributed/peers?output_mode=json"

# REST : cycles de replication recents
curl -k -u admin:<password> \
  "https://shcMember01.example.com:8089/services/search/distributed/bundle/replication/cycles?output_mode=json"

# Sur le peer suspect : etat des bundles recus
ls -la $SPLUNK_HOME/var/run/searchpeers/ | head -20
```

**Lecture rapide.**

1. `splunk show distributed-peers` : tous les peers up et atteints récemment ?
2. `splunk list distributed-peer` : alternative — comparer si divergence.
3. REST `/services/search/distributed/peers` : hash bundle SH-déclaré par peer.
4. REST `/services/search/distributed/bundle/replication/cycles` : historique cycles, échecs récents ?
5. `ls var/run/searchpeers/` côté peer : quels GUID source ? quel hash le plus récent par GUID ?

**Décision.** Si 1 montre peer down : chap. 05 branche D. Si 3 montre hashes divergents entre peers : chap. 05 branche E. Si 5 montre un GUID absent ou un hash ancien : combiner branches D + E.

## 3. Triage en 5 commandes — configuration bundle indexer cluster

À jouer face à « `splunk apply cluster-bundle` échoue » ou « un peer indexer ne voit pas la nouvelle conf ».

```bash
# Sur le CM
splunk validate cluster-bundle --check-restart -auth admin:<password>
splunk show cluster-bundle-status -auth admin:<password>

# REST : etat global du CM
curl -k -u admin:<password> \
  "https://cm01.example.com:8089/services/cluster/manager/info?output_mode=json"

# REST : etat des peers indexer cluster
curl -k -u admin:<password> \
  "https://cm01.example.com:8089/services/cluster/manager/peers?output_mode=json"

# Sur le peer indexer suspect
splunk btool clustering list
```

**Lecture rapide.**

1. `splunk validate cluster-bundle --check-restart` : le bundle est valide ? quels peers vont restart ?
2. `splunk show cluster-bundle-status` : état de propagation aux peers.
3. REST `/services/cluster/manager/info` : RF / SF respectés ? captain CM stable ?
4. REST `/services/cluster/manager/peers` : peer en état dégradé ?
5. `splunk btool clustering list` côté peer suspect : `pass4SymmKey` cohérent ? `manager_uri` correct ?

**Décision.** Cf. doc Splunk [Configurationbundleissues](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Configurationbundleissues) pour le traitement spécifique de chaque cas.

## 4. Top 5 filtres `splunkd.log` à griller

À copier dans un shell, lancer côté nœud suspect. (`$SPLUNK_HOME` = `/opt/splunk` ou équivalent selon installation.)

```bash
# 1. Erreurs replication knowledge bundle (cote SH)
grep -E "DistributedBundleReplicationManager.*(WARN|ERROR)" \
  $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -50

# 2. Conf replication interne SHC (cote captain)
grep "ConfReplicationThread" \
  $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -50

# 3. Apply cluster-bundle recus (cote peer indexer)
grep "ApplyBundleHandler" \
  $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -50

# 4. Coordination SHC interne (election captain)
grep -E "SHCMaster|RaftConsensus" \
  $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -50

# 5. Filet large : toute erreur contenant "bundle"
grep -iE "(WARN|ERROR).*bundle" \
  $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -100
```

**Conventions.** `DistributedBundleReplicationManager` est le composant documenté Splunk. Les autres composants (`ConfReplicationThread`, `ApplyBundleHandler`, `SHCMaster`) sont observés empiriquement — leur présence dans `splunkd.log` de votre version 9.4 mineure doit être vérifiée si vous bâtissez du monitoring dessus.

## 5. Top 5 SPL `index=_internal`

À coller dans un onglet SH, time range explicite, lecture immédiate.

```spl
# 1. Erreurs replication bundle SH peers sur 1h, par SH et message
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager log_level=ERROR earliest=-1h@m latest=now
| stats count by host, message
| sort -count
```

```spl
# 2. Activite bundle recente, par SH
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager "bundle" earliest=-1h@m latest=now
| stats latest(_time) as last_seen by host, message
| sort -last_seen
```

```spl
# 3. Trace des apply SHC bundle sur 24h
index=_internal sourcetype=splunkd "shcluster-bundle" earliest=-24h@h latest=now
| stats count by host, log_level
| sort host
```

```spl
# 4. Erreurs apply cluster-bundle (indexer cluster) sur 24h
index=_internal sourcetype=splunkd "cluster-bundle" (log_level=WARN OR log_level=ERROR) earliest=-24h@h latest=now
| stats count by host, message
| sort -count
```

```spl
# 5. Appels REST shcluster bundle (access log), 1h
index=_internal sourcetype=splunkd_access uri_path="*shcluster*bundle*" earliest=-1h@m latest=now
| stats count by host, uri_path, status
| sort -count
```

## 6. Décisions rapides — par symptôme

| Symptôme observé | Première action | Renvoi |
| --- | --- | --- |
| `apply shcluster-bundle` échoue | §1 — 5 commandes triage SHC | Chap. 05 branche A |
| Membre SHC divergent | §1 — vérifier `bundle_id` par membre | Chap. 05 branche B |
| Bundle trop gros | `du -sh etc/apps/*` et `etc/shcluster/apps/*` | Chap. 05 branche C |
| Peer ne reçoit pas | §2 — REST `/services/search/distributed/peers` | Chap. 05 branche D |
| Hashes divergents | §2 — REST `cycles` + `ls var/run/searchpeers/` | Chap. 05 branche E |
| RF SHC non respecté | §1 — `splunk show shcluster-status` | Chap. 05 branche F |
| Mounted obsolète | §2 — `ls -la` partage + côté peer | Chap. 05 branche G |
| Recherche bloquée | §4 — composant `DistributedBundleReplicationManager` | Chap. 05 branche H |
| Apply cluster-bundle KO | §3 — `validate cluster-bundle --check-restart` | Chap. 05 branche I + [Configurationbundleissues](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Configurationbundleissues) |

## 7. Garde-fous

- Toujours `splunk validate cluster-bundle --check-restart` **avant** `splunk apply cluster-bundle`.
- Toujours `splunk apply shcluster-bundle -action stage` **avant** l'apply complet, pour valider le packaging.
- Toujours `splunk list shcluster-bundle-status` côté captain **après** un apply, avant de considérer la propagation comme effective.
- Toujours `grep ERROR $SPLUNK_HOME/var/log/splunk/splunkd.log` côté nœud suspect avant d'ouvrir un demande Splunk Support — souvent la cause est là.
- Si un peer accumule des `WARN DistributedBundleReplicationManager - bundle replication ... took too long` : la réplication est asynchrone (le peer sert avec son bundle précédent, recherches non bloquées) mais le knowledge poussé récemment n'est pas reflété — traiter la cause (peer KO, lien lent, bundle volumineux) plutôt que de masquer l'avertissement.

## Sources

- [Splunk DistSearch 9.4 — View SHC status](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus)
- [Splunk DistSearch 9.4 — Troubleshoot knowledge bundle replication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Troubleshootknowledgebundlereplication)
- [Splunk Indexer 9.4 — Configuration bundle issues](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Configurationbundleissues)
- [Splunk Indexer 9.4 — Update peer configurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Updatepeerconfigurations)
- [Splunk REST API 9.4 — Cluster endpoints](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster)
