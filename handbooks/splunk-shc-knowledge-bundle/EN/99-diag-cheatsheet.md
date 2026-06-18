# Chapter 99 — Quick diag cheatsheet

> One printable page. The right order of the first commands to type facing a bundle incident, without thinking. Three triage sections (SHC bundle, search knowledge bundle, indexer cluster bundle), a logs section, an SPL section. The commands cited are detailed in ch. 06.

## Quick refresher

- Before anything: **identify which bundle is at stake** (see ch. 00 §2). Three mechanics carry the word.
- All the commands below use `-auth admin:<password>`; in production, prefer a token.
- If quick diag does not settle it in 5 minutes, move to ch. 05 (full tree).

## 1. Triage in 5 commands — SHC configuration bundle

To run facing "`splunk apply shcluster-bundle` seems to do nothing" or "an SHC member does not have the latest app".

```bash
# On the deployer
splunk status
splunk show shcluster-bundle-status -auth admin:<password>

# On any SHC member (redirects to captain)
splunk show shcluster-status -auth admin:<password>
splunk list shcluster-bundle-status -auth admin:<password>
splunk list shcluster-member-info -auth admin:<password>
```

**Quick read.**

1. `splunk status` (deployer): splunkd up?
2. `splunk show shcluster-bundle-status` (deployer): last push successful? `last_apply_time` recent?
3. `splunk show shcluster-status` (member): captain stable? all members up? RF honored?
4. `splunk list shcluster-bundle-status` (captain): `bundle_id` consistent between all members?
5. `splunk list shcluster-member-info` (member): GUID, kvstore state, mode.

**Decision.** If 1-3 OK and 4 divergent: ch. 05 branch B. If 1 KO: ch. 05 branch A1. If 3 shows captain missing: ch. 05 branch A2.

## 2. Triage in 5 commands — search knowledge bundle

To run facing "search stuck waiting for bundle" or "a peer does not see the latest lookup".

```bash
# On the SH (or SHC member acting as SH)
splunk show distributed-peers -auth admin:<password>
splunk list distributed-peer -auth admin:<password>

# REST: detailed state of peers
curl -k -u admin:<password> \
  "https://shcMember01.example.com:8089/services/search/distributed/peers?output_mode=json"

# REST: recent replication cycles
curl -k -u admin:<password> \
  "https://shcMember01.example.com:8089/services/search/distributed/bundle/replication/cycles?output_mode=json"

# On the suspect peer: state of received bundles
ls -la $SPLUNK_HOME/var/run/searchpeers/ | head -20
```

**Quick read.**

1. `splunk show distributed-peers`: all peers up and reached recently?
2. `splunk list distributed-peer`: alternative — compare if divergence.
3. REST `/services/search/distributed/peers`: SH-declared bundle hash per peer.
4. REST `/services/search/distributed/bundle/replication/cycles`: cycle history, recent failures?
5. `ls var/run/searchpeers/` on the peer side: which source GUIDs? which most recent hash per GUID?

**Decision.** If 1 shows peer down: ch. 05 branch D. If 3 shows divergent hashes between peers: ch. 05 branch E. If 5 shows a missing GUID or an old hash: combine branches D + E.

## 3. Triage in 5 commands — indexer cluster configuration bundle

To run facing "`splunk apply cluster-bundle` fails" or "an indexer peer does not see the new conf".

```bash
# On the CM
splunk validate cluster-bundle --check-restart -auth admin:<password>
splunk show cluster-bundle-status -auth admin:<password>

# REST: global CM state
curl -k -u admin:<password> \
  "https://cm01.example.com:8089/services/cluster/manager/info?output_mode=json"

# REST: indexer cluster peers state
curl -k -u admin:<password> \
  "https://cm01.example.com:8089/services/cluster/manager/peers?output_mode=json"

# On the suspect indexer peer
splunk btool clustering list
```

**Quick read.**

1. `splunk validate cluster-bundle --check-restart`: is the bundle valid? which peers will restart?
2. `splunk show cluster-bundle-status`: state of propagation to the peers.
3. REST `/services/cluster/manager/info`: RF / SF honored? CM captain stable?
4. REST `/services/cluster/manager/peers`: peer in degraded state?
5. `splunk btool clustering list` on the suspect peer side: `pass4SymmKey` consistent? `manager_uri` correct?

**Decision.** See the Splunk doc [Configurationbundleissues](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Configurationbundleissues) for the case-specific treatment.

## 4. Top 5 `splunkd.log` filters to grill

To copy into a shell, run on the suspect node side. (`$SPLUNK_HOME` = `/opt/splunk` or equivalent depending on the install.)

```bash
# 1. Knowledge bundle replication errors (on the SH)
grep -E "DistributedBundleReplicationManager.*(WARN|ERROR)" \
  $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -50

# 2. SHC internal conf replication (on the captain)
grep "ConfReplicationThread" \
  $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -50

# 3. Received apply cluster-bundle (on the indexer peer)
grep "ApplyBundleHandler" \
  $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -50

# 4. SHC internal coordination (captain election)
grep -E "SHCMaster|RaftConsensus" \
  $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -50

# 5. Wide net: any error containing "bundle"
grep -iE "(WARN|ERROR).*bundle" \
  $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -100
```

**Conventions.** `DistributedBundleReplicationManager` is the Splunk-documented component. The other components (`ConfReplicationThread`, `ApplyBundleHandler`, `SHCMaster`) are observed empirically — their presence in `splunkd.log` of your 9.4 minor version must be verified if you build monitoring on top of them.

## 5. Top 5 SPL `index=_internal`

To paste in an SH tab, explicit time range, immediate read.

```spl
# 1. SH peers bundle replication errors over 1h, by SH and message
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager log_level=ERROR earliest=-1h@m latest=now
| stats count by host, message
| sort -count
```

```spl
# 2. Recent bundle activity, per SH
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager "bundle" earliest=-1h@m latest=now
| stats latest(_time) as last_seen by host, message
| sort -last_seen
```

```spl
# 3. Trace of SHC bundle applies over 24h
index=_internal sourcetype=splunkd "shcluster-bundle" earliest=-24h@h latest=now
| stats count by host, log_level
| sort host
```

```spl
# 4. apply cluster-bundle (indexer cluster) errors over 24h
index=_internal sourcetype=splunkd "cluster-bundle" (log_level=WARN OR log_level=ERROR) earliest=-24h@h latest=now
| stats count by host, message
| sort -count
```

```spl
# 5. REST shcluster bundle calls (access log), 1h
index=_internal sourcetype=splunkd_access uri_path="*shcluster*bundle*" earliest=-1h@m latest=now
| stats count by host, uri_path, status
| sort -count
```

## 6. Quick decisions — by symptom

| Observed symptom | First action | Forward to |
| --- | --- | --- |
| `apply shcluster-bundle` fails | §1 — 5 SHC triage commands | Ch. 05 branch A |
| Divergent SHC member | §1 — check `bundle_id` per member | Ch. 05 branch B |
| Bundle too large | `du -sh etc/apps/*` and `etc/shcluster/apps/*` | Ch. 05 branch C |
| Peer not receiving | §2 — REST `/services/search/distributed/peers` | Ch. 05 branch D |
| Divergent hashes | §2 — REST `cycles` + `ls var/run/searchpeers/` | Ch. 05 branch E |
| SHC RF not honored | §1 — `splunk show shcluster-status` | Ch. 05 branch F |
| Stale mounted | §2 — `ls -la` share + on the peer side | Ch. 05 branch G |
| Search stuck | §4 — component `DistributedBundleReplicationManager` | Ch. 05 branch H |
| Apply cluster-bundle KO | §3 — `validate cluster-bundle --check-restart` | Ch. 05 branch I + [Configurationbundleissues](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Configurationbundleissues) |

## 7. Safeguards

- Always `splunk validate cluster-bundle --check-restart` **before** `splunk apply cluster-bundle`.
- Always `splunk apply shcluster-bundle -action stage` **before** the full apply, to validate packaging.
- Always `splunk list shcluster-bundle-status` on the captain side **after** an apply, before considering propagation effective.
- Always `grep ERROR $SPLUNK_HOME/var/log/splunk/splunkd.log` on the suspect node side before opening a Splunk Support case — the cause is often there.
- In an emergency with `allowSkipReplication=true` enabled to unblock: document the time window (date, reason) and plan the return to `false` as soon as the incident is closed.

## Sources

- [Splunk DistSearch 9.4 — View SHC status](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus)
- [Splunk DistSearch 9.4 — Troubleshoot knowledge bundle replication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Troubleshootknowledgebundlereplication)
- [Splunk Indexer 9.4 — Configuration bundle issues](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Configurationbundleissues)
- [Splunk Indexer 9.4 — Update peer configurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Updatepeerconfigurations)
- [Splunk REST API 9.4 — Cluster endpoints](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster)
