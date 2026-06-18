# Chapter 6 — Investigations: toolbox

> This chapter is the **reference** consulted facing an incident. Four exhaustive tables — CLI, REST, `splunkd.log` filters, SPL `index=_internal` — list the useful commands and queries, with their Splunk 9.4 documentation source where it exists and the "observed empirically" tag when the component or endpoint has no dedicated reference page. The chapter closes with three typical combos ("deployer health in 3 commands", "divergent hash in 4 SPLs", "lost peer in 2 REST calls") that condense the most frequent sequences.

## Quick refresher

- The commands cited here are **all** the ones used in the decision tree of ch. 05. When ch. 05 says "see ch. 06 §N", it is here.
- Among the `splunkd.log` components relevant to the bundle, Splunk only documents `DistributedBundleReplicationManager` individually. The other components used in diag are marked "observed empirically — not documented by Splunk". To grep for on a real 9.4 `splunkd.log` to confirm their presence in your version.
- All REST commands use the default mgmt port `8089` and basic authentication. In production, prefer a Splunk token (see Splunk docs).
- The `index=_internal` SPL listed are ready to paste — explicit time range, target hosts anonymized.

## 1. Investigation CLI

The table below is meant to be reproduced in a local cheat-sheet. Each command is preceded by the execution node (deployer / captain / SHC member / SH / CM / indexer peer).

| Command | Description | Splunk 9.4 source |
| --- | --- | --- |
| `splunk apply shcluster-bundle -target https://captain01.example.com:8089 -auth admin:<password>` (on deployer) | Pushes the SHC configuration bundle from the deployer to the captain. Options `-action stage|send`, `-preserve-lookups`, `-push-default-app-conf`. | [PropagateSHCconfigurationchanges](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/PropagateSHCconfigurationchanges) |
| `splunk show shcluster-bundle-status -auth admin:<password>` (on deployer) | State of the last bundle push from the deployer to the captain. | [ViewSHCstatus](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus) |
| `splunk list shcluster-bundle-status -auth admin:<password>` (on captain) | State of propagation to SHC members: `bundle_id` per member. | [ViewSHCstatus](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus) |
| `splunk show shcluster-status -auth admin:<password>` (on any member) | Global SHC state: current captain, members and their states, replication ports. | [ViewSHCstatus](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus) |
| `splunk list shcluster-member-info -auth admin:<password>` (on any member) | Details of the current member: GUID, mode, kvstore state. | [ViewSHCstatus](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus) |
| `splunk rolling-restart shcluster-members -auth admin:<password>` (on captain) | Rolling restart of SHC members, useful after an apply with a change requiring restart. | [ViewSHCstatus](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus) |
| `splunk apply cluster-bundle --answer-yes -auth admin:<password>` (on CM) | Pushes the indexer cluster configuration bundle from the CM to the indexer peers. | [Updatepeerconfigurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Updatepeerconfigurations) |
| `splunk validate cluster-bundle --check-restart -auth admin:<password>` (on CM) | Validates the indexer cluster configuration bundle before push, predicts the peers that will require restart. | [Updatepeerconfigurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Updatepeerconfigurations) |
| `splunk show cluster-bundle-status -auth admin:<password>` (on CM) | State of indexer cluster bundle propagation to the peers. | [Updatepeerconfigurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Updatepeerconfigurations) |
| `splunk show cluster-manager-status -auth admin:<password>` (on CM) | Global state of the indexer cluster manager: known peers, replication/search factor, service state. Cited by ch. 05 D1. | Observed empirically — CLI counterpart of the REST endpoint `/services/cluster/manager/info`. |
| `splunk show cluster-manager-peers -auth admin:<password>` (on CM) | List of indexer peers known to the cluster manager with their state. Cited by ch. 05 H3. | Observed empirically — CLI counterpart of the REST endpoint `/services/cluster/manager/peers`. |
| `splunk rolling-restart cluster-peers -auth admin:<password>` (on CM) | Rolling restart of indexer cluster peers after a cluster-bundle that requires restart. | [Restartthecluster](https://docs.splunk.com/Documentation/Splunk/9.4.2/Indexer/Restartthecluster) |
| `splunk list distributed-peer -auth admin:<password>` (on SH) | Lists the distributed-search peers known to the SH and their state. The exact form of the subcommand may vary; `splunk help distributed` confirms it on the instance. | [Configuredistributedsearch](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Configuredistributedsearch) |
| `splunk show distributed-peers -auth admin:<password>` (on SH) | Alternative to the previous one — often more readable output. Includes the SH-declared bundle hash where relevant. | [Configuredistributedsearch](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Configuredistributedsearch) |
| `splunk btool check` (on any node) | Checks consistency of loaded `.conf` (useful in diag A3: rejected validation). | Observed empirically — documented indirectly in the Splunk Troubleshooting Manual. |
| `splunk btool clustering list` (on SH / peer / CM) | Shows the effective `[clustering]` stanza after `.conf` merge. Useful in diag D3 (divergent pass4SymmKey). | Observed empirically — documented indirectly. |
| `splunk status` (on any node) | State of the splunkd process. Useful in diag A1 (deployer down). | [WhatSplunklogsaboutitself](https://docs.splunk.com/Documentation/Splunk/9.4.2/Troubleshooting/WhatSplunklogsaboutitself) |

> Note: `splunk show shcluster-bundle-status` (deployer-side) vs `splunk list shcluster-bundle-status` (captain-side) — `show` is the state of the **last push made**, `list` is the state of **propagation to the members**. The two are complementary in diag.

## 2. Investigation REST

The REST endpoints below are queried through `curl -k -u admin:<password> https://<host>:8089/...`. Add `?output_mode=json` for output usable in a script.

| Endpoint | Method | Description | Splunk 9.4 source |
| --- | --- | --- | --- |
| `/services/shcluster/captain/info` | GET | Captain info: term duration, ID, SHC state. To query on the captain (or on a member — the request is redirected). | [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster) |
| `/services/shcluster/captain/members` | GET | List of SHC members seen by the captain, with their state and their current `bundle_id`. | [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster) |
| `/services/shcluster/member/info` | GET | Local member info — to query on each member individually to compare. | [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster) |
| `/services/cluster/manager/info` | GET | Cluster manager state (indexer cluster, 9.4 terminology). | [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster) |
| `/services/cluster/manager/peers` | GET | List of indexer cluster peers, bucket state, replication state. | [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster) |
| `/services/cluster/manager/control/default/apply` | POST | Triggers the indexer cluster configuration bundle apply (CLI equivalent: `splunk apply cluster-bundle`). | [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster) |
| `/services/cluster/config` | GET | Exposed cluster manager configuration. Useful to check `replication_factor`, `search_factor`. | [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster) |
| `/services/search/distributed/peers` | GET | On SH: distributed-search peers and their state (incl. SH-declared bundle hash when exposed). | [RESTprolog](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTprolog) |
| `/services/search/distributed/bundle/replication/config` | GET | Current configuration of SH → peers knowledge bundle replication (effective parameters after merge). | [Troubleshootknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Troubleshootknowledgebundlereplication) |
| `/services/search/distributed/bundle/replication/cycles` | GET | History of SH → peers bundle replication cycles: timestamp, target peers, state, size. This is the main endpoint to characterize a recent failure. | [Troubleshootknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Troubleshootknowledgebundlereplication) |

> Note: some `/services/admin/*` endpoints may exist and return useful information, but Splunk explicitly asks **not to document them publicly** nor to automate against them. They are treated in ch. 07 as a pitfall (a temptation to avoid) and are not in this table.

### Concrete examples

```bash
# On the SH: state of all distributed-search peers (JSON)
curl -k -u admin:<password> \
  "https://shcMember01.example.com:8089/services/search/distributed/peers?output_mode=json" \
  | jq '.entry[] | {name, "status": .content.status, "build": .content.build}'

# On the captain: state of SHC bundle propagation to the members
curl -k -u admin:<password> \
  "https://captain01.example.com:8089/services/shcluster/captain/members?output_mode=json" \
  | jq '.entry[] | {name, "status": .content.status, "bundle_id": .content.bundle_id}'

# On the SH: history of SH peers bundle replication cycles
curl -k -u admin:<password> \
  "https://shcMember01.example.com:8089/services/search/distributed/bundle/replication/cycles?output_mode=json"
```

## 3. `splunkd.log` filters

The table below lists the components to grep for in `splunkd.log` (indexed `index=_internal sourcetype=splunkd`). Splunk only documents `DistributedBundleReplicationManager` individually among those relevant to the bundle; the others are marked "observed empirically".

| Filter (component) | What to watch | Source / status |
| --- | --- | --- |
| `component=DistributedBundleReplicationManager` | SH → peers bundle replication cycles, size errors, timeouts, hash divergence on the SH side. This is **the** main documented component. | [Troubleshootknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Troubleshootknowledgebundlereplication) |
| `component=ApplyBundleHandler` (to confirm by grep) | Reception on the peer side of an apply cluster-bundle (indexer cluster). | Observed empirically — *not documented by Splunk* individually |
| `component=ConfReplicationThread` (to confirm by grep) | SHC internal conf replication (post-deployer apply). Cycles, pushed/pulled objects. | Observed empirically — *not documented by Splunk* individually |
| `component=ConfReplication*` (prefix — to confirm by grep) | Variants of the above component depending on 9.x minor version. | Observed empirically |
| `component=CMMaster` | Indexer cluster manager (legacy `master` terminology still present in 9.4 logs for backward compatibility). | Observed empirically — *not documented by Splunk* individually |
| `component=CMPeer` | Indexer cluster peer (legacy `peer` terminology). | Observed empirically — *not documented by Splunk* individually |
| `component=SHCMaster` (variants by version) | SHC internal coordination, captain election. | Observed empirically |
| `component=SHCSchedulerDelegator` (to confirm by grep) | SHC-side decision to execute a clustered saved search on the captain. | Observed empirically — *not documented by Splunk* individually |
| `log_level=ERROR OR log_level=WARN` + `bundle` in message | Wide net for untyped bundle errors. First triage reflex. | Standard practice |

### Sample lines

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

### Grep recommendations

```bash
# On the SH: last bundle replication cycles, errors highlighted
grep -E "DistributedBundleReplicationManager.*(WARN|ERROR)" \
  $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -50

# On the captain: last SHC internal conf replication cycles
grep "ConfReplicationThread" $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -50

# On the indexer peer: reception of apply cluster-bundle
grep "ApplyBundleHandler" $SPLUNK_HOME/var/log/splunk/splunkd.log | tail -50
```

## 4. SPL `index=_internal` — ready-to-paste searches

Five consolidated searches, explicit time range, hosts anonymized in the examples (all use `host` as output to identify the node, no input prefixing).

### 4.1. SH → peers knowledge bundle replication errors over 24h

```spl
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager log_level=ERROR earliest=-24h@h latest=now
| stats count by host, message
| sort -count
```

**Goal.** Identify SHs producing errors and the dominant messages. Lets you prioritize the node to investigate first. Source: Splunk-documented component.

### 4.2. Recent bundle activity, per SH

```spl
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager "bundle" earliest=-1h@m latest=now
| stats latest(_time) as last_seen by host, message
| sort -last_seen
```

**Goal.** See whether replication is currently running (`last_seen` should be recent) and whether it produces abnormal messages. Source: Splunk-documented component.

### 4.3. Trace of `apply shcluster-bundle` over 7 days

```spl
index=_internal sourcetype=splunkd "shcluster-bundle" earliest=-7d@d latest=now
| stats count by host, log_level
| sort host
```

**Goal.** History of SHC bundle applies. The keyword is reliable (it is the subcommand name). Source: searched keyword — reliable as it is a command name.

### 4.4. apply cluster-bundle (indexer cluster) errors over 7 days

```spl
index=_internal sourcetype=splunkd "cluster-bundle" (log_level=WARN OR log_level=ERROR) earliest=-7d@d latest=now
| stats count by host, message
| sort -count
```

**Goal.** Recent errors on the CM or peers side on cluster-bundle applies. Source: searched keyword.

### 4.5. Received shcluster bundle REST calls, access-log view

```spl
index=_internal sourcetype=splunkd_access uri_path="*shcluster*bundle*" earliest=-1h@m latest=now
| stats count by host, uri_path, status
| sort -count
```

**Goal.** See who calls which shcluster bundle endpoints and with which return code. Useful to identify a supervision script's calls or trace a push that did not complete. Source: standard Splunk sourcetype.

### 4.6. (Bonus) Hash convergence — routine metric

This SPL is not in the §7.4 table of the spec, but its logic is mentioned in ch. 05 §12 (routine metrics). It requires cross-referencing the SH-declared state and the peer-effective state that Splunk does not provide in a single endpoint; in practice, the admin implements it as a scheduled saved search feeding a summary index, aggregating each peer's `splunkd.log` (entry `received bundle hash=...`). Pattern:

```spl
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager "received" earliest=-1h@m latest=now
| rex "hash=(?<hash>[a-f0-9]+)"
| stats values(hash) as hashes count by host
| where mvcount(hashes) > 1
```

**Interpretation.** Any `host` with `mvcount(hashes) > 1` over a short window has seen several hashes — indicator of frequent cycles (normal under high activity) or of divergence (to correlate with the current SH hash).

## 5. Typical combos

### 5.1. Deployer health in 3 commands

To run when facing the symptom "apply shcluster-bundle seems to do nothing".

```bash
# 1. Deployer process state
splunk status

# 2. Last push performed from the deployer
splunk show shcluster-bundle-status -auth admin:<password>

# 3. Global SHC state seen from a member (captain stable?)
splunk show shcluster-status -auth admin:<password>
```

Reading: (1) must show splunkd up. (2) must show a recent `last_apply_time` and a consistent `bundle_id`. (3) must show a stable captain and all members up.

### 5.2. Divergent hash in 4 SPL

To run when facing the symptom "two SH members see the peers in different states".

```spl
# 1. Which SHs are actively producing cycles?
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager "cycle" earliest=-1h@m latest=now
| stats latest(_time) as last_cycle by host
| sort -last_cycle

# 2. Which cycles failed recently?
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager log_level=ERROR earliest=-1h@m latest=now
| stats count by host, message

# 3. Which peers are in fault?
index=_internal sourcetype=splunkd component=DistributedBundleReplicationManager "peer=" earliest=-1h@m latest=now
| rex "peer=(?<peer>[\w\.-]+)"
| stats count by host, peer, log_level

# 4. Access-log view: recent REST calls to bundle endpoints
index=_internal sourcetype=splunkd_access uri_path="*distributed*bundle*" earliest=-1h@m latest=now
| stats count by host, uri_path, status
```

Reading: (1) characterizes activity per SH. (2) lists recent errors. (3) isolates the offending peers. (4) confirms on the HTTP side that the calls arrive and with which code.

### 5.3. Lost peer in 2 REST calls

To run when facing the symptom "one particular peer no longer receives the bundle".

```bash
# 1. Peer state as seen from the SH
curl -k -u admin:<password> \
  "https://shcMember01.example.com:8089/services/search/distributed/peers?output_mode=json" \
  | jq '.entry[] | select(.name | contains("peer02")) | {name, "status": .content.status, "build": .content.build}'

# 2. Peer state as seen from the CM
curl -k -u admin:<password> \
  "https://cm01.example.com:8089/services/cluster/manager/peers?output_mode=json" \
  | jq '.entry[] | select(.name | contains("peer02")) | {name, "status": .content.status}'
```

Reading: (1) state as seen from the SH (down? quarantined?). (2) state as seen from the CM (enrolled? active?). A divergence between the two views (peer up on the CM side, down on the SH side) points to a routing / `serverList` problem on the SH side.

## 6. When to escalate / when to decide

- **Always start with a tight time sample** (`earliest=-1h@m`) before broadening. The mass of `_internal` is enough that 7-day searches are expensive.
- **Anonymize outputs** when copying a result into a support request or an email. Real hostnames have no place outside the internal operational perimeter.
- **Do not mix investigation searches and alerting** in the same saved search. Investigation searches are ad-hoc, short window. Alerts are scheduled, fixed window, thresholds.
- **Consistency probe**: before believing in a Splunk bug, check two to three consistent elements (CLI + REST + log) on the same symptom. A divergence between sources of truth internal to the node is itself a symptom.

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
