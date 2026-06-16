# Splunk indexer cluster — site id change

Generic change plan for renaming or reassigning the `site` attribute of one
or more indexers in a Splunk indexer cluster (multisite or single-site
becoming multisite). Treat this fiche as a **template**: every value in
angle brackets must be confirmed against the target deployment before
execution.

## 1. Generic description of the change

In a Splunk indexer cluster, each cluster member declares which **site** it
belongs to via the `site` attribute in `server.conf`
(`[general] site = <siteX>`). The cluster manager uses these site labels
together with `site_replication_factor` and `site_search_factor` to decide
how bucket copies are placed and which copies are searchable.

A "site id change" covers any of the following variants:

- **Rename**: the cluster keeps the same topology but the label `<old_site>`
  becomes `<new_site>` on a set of indexers (and on the cluster manager's
  `available_sites` list).
- **Reassignment**: an indexer that used to belong to `<site_a>` is moved to
  `<site_b>` (e.g. physical relocation, datacenter reorganization).
- **Topology change**: single-site cluster (`site = site0`) becoming
  multisite, or the reverse. This variant has the largest blast radius and
  requires extra steps that are flagged inline below.

The change touches:

- Each affected indexer's `server.conf` (`[general] site`).
- The cluster manager's `server.conf` (`[clustering] available_sites`,
  `site_replication_factor`, `site_search_factor`, and possibly
  `multisite`).
- The search heads' `server.conf` (`[general] site`) when site-based search
  affinity is in use.
- Forwarder configurations using `indexerDiscovery` or
  `site_failover` directives, when present.

The goal of the change is to make the cluster's site topology reflect a new
operational reality (relocation, renaming, segmentation) **without** data
loss, and with bucket counts converging back to the configured replication
and search factors after the change.

## 2. Risks and service interruption

### Risks

- **Bucket fixup storm**: changing site labels triggers the manager to
  re-evaluate per-site bucket placement. The cluster will start a fixup
  cycle that can move and replicate large volumes of data between peers.
  Network and disk I/O on indexers will spike for the duration of fixup.
- **Replication/Search factor violations**: until fixup completes, the
  cluster will report `Replication Factor not met` or `Search Factor not
  met`. Some buckets may briefly be searchable from fewer sites than
  intended.
- **Search affinity disruption**: if search heads also have a `site`
  attribute and `site_search_affinity = true`, queries may suddenly hit a
  different set of indexers after the change, with cold-cache search
  latency.
- **Misalignment between manager and peers**: the manager configuration
  (`available_sites`, RF/SF) must list every site label declared by peers,
  otherwise affected peers will be rejected from the cluster.
- **Indexer discovery breakage**: forwarders configured for site-aware
  indexer discovery may stop routing correctly until they pick up the new
  manager view.
- **Splunkd restart loop**: an inconsistent `server.conf` (typos in
  `site = …`, missing closing brackets) will prevent the peer from
  rejoining; rollback may be needed before fixup even starts.
- **Multisite-only features** become active when going from single-site to
  multisite: site-aware search, summary replication, and bucket affinity all
  start to consume additional resources.

### Service interruption

- **Ingest**: usually no full outage. Forwarders with autoLB and a healthy
  cluster manager keep sending data; expect transient backoffs while the
  affected peer restarts.
- **Search**: short interruption when the manager re-evaluates the
  generation. Saved searches and dashboards may show partial results for a
  few minutes around each peer restart.
- **Cluster availability**: degraded (yellow) state for the entire fixup
  duration; **not** an outage, but alerting on cluster health will fire.
- **Estimated duration**: peer restart is seconds; fixup is a function of
  total bucket count, RF/SF, and inter-peer bandwidth — minutes for a
  small cluster, hours for a large one. Confirm against historical fixup
  metrics from earlier maintenance.

## 3. Change plan

The order below assumes a rolling change so the cluster never loses quorum
nor drops below the configured RF/SF. Adjust if the target deployment has
maintenance windows that allow a fuller stop.

### 3.1 Pre-change

1. **Snapshot the current topology** for the rollback plan:
   ```bash
   splunk show cluster-status -auth <admin>:<password>
   splunk list cluster-config -auth <admin>:<password>
   splunk btool server list clustering --debug
   splunk btool server list general --debug
   ```
   Persist the output of these commands somewhere outside the cluster
   nodes (the rollback procedure depends on it).
2. **Capture bucket health baseline**: number of buckets, RF/SF status, list
   of buckets currently in fixup. The change should converge back to this
   baseline (or better) after completion.
3. **Confirm cluster manager is healthy** and the `splunkd.log` of the
   manager is clean (no recurring fixup errors).
4. **Pause ingestion-sensitive jobs** (summary indexing, alerting
   playbooks) for the maintenance window if they cannot tolerate brief
   degraded states.
5. **Enable maintenance mode** on the cluster manager to suppress fixup
   while you reconfigure peers:
   ```bash
   splunk enable maintenance-mode -auth <admin>:<password>
   ```

### 3.2 Cluster manager configuration

1. Update `server.conf` on the **cluster manager**:
   ```ini
   [clustering]
   mode = manager
   multisite = true                           ; required if going multisite
   available_sites = <site1>,<site2>,<siteN>  ; full list including new labels
   site_replication_factor = origin:<r>, total:<R>
   site_search_factor      = origin:<s>, total:<S>
   ```
2. Validate the syntax before restarting:
   ```bash
   splunk btool server list clustering --debug
   ```
3. Restart `splunkd` on the manager:
   ```bash
   splunk restart
   ```
4. Confirm the manager comes back up and the new `available_sites` list is
   visible in `cluster-config`.

### 3.3 Indexer reconfiguration (rolling)

For each affected indexer, one at a time:

1. Edit `server.conf`:
   ```ini
   [general]
   site = <new_site>
   ```
2. (Optional) verify with `splunk btool server list general --debug` that
   no other `[general]` section overrides `site`.
3. Restart `splunkd`:
   ```bash
   splunk restart
   ```
4. Wait for the peer to rejoin the cluster:
   ```bash
   splunk show cluster-status -auth <admin>:<password>
   ```
   Confirm the peer reports `Up` and its `Site` field shows `<new_site>`.
5. Move to the next indexer **only** after the previous one is fully
   rejoined.

### 3.4 Search head reconfiguration (if applicable)

If `site_search_affinity` is enabled or search heads carry a `site`
attribute:

1. Update each search head's `server.conf`:
   ```ini
   [general]
   site = <new_site_for_this_sh>
   ```
2. Restart `splunkd` on the search head.
3. For a search head cluster, do this one member at a time and confirm
   captaincy is not lost.

### 3.5 Exit maintenance and fixup

1. Disable maintenance mode on the cluster manager:
   ```bash
   splunk disable maintenance-mode -auth <admin>:<password>
   ```
2. Watch fixup start and progress:
   ```bash
   splunk show cluster-status -auth <admin>:<password>
   splunk list excess-buckets -auth <admin>:<password>
   ```
3. Let the cluster converge before declaring the change complete. Do not
   schedule any other intrusive operation while fixup runs.

## 4. Rollback plan

### 4.1 Decision criteria for rolling back

Trigger rollback if any of the following occur:

- A reconfigured peer fails to rejoin the cluster after restart and the
  cause is not a trivial typo correctable in minutes.
- The cluster reports a hard `Replication Factor not met` for buckets that
  were previously compliant, and fixup is not making forward progress
  (no decrease in non-compliant buckets over a sustained window).
- Search results return systematic gaps that map to the site change (not
  just transient cold-cache latency).
- The cluster manager itself becomes unstable after its own restart.

### 4.2 Rollback steps

1. **Re-enable maintenance mode** on the cluster manager.
2. On each affected indexer, restore the previous `server.conf`
   `[general] site = <old_site>` value and restart `splunkd`.
3. On the cluster manager, restore the previous `[clustering]` block
   (especially `available_sites`, `multisite`, RF/SF) and restart
   `splunkd`.
4. On affected search heads, restore the previous `[general] site` value
   and restart `splunkd`.
5. **Disable maintenance mode** and let the cluster converge back to its
   original state.
6. Compare `cluster-status` and bucket counts against the pre-change
   snapshot taken in 3.1. The numbers should match within a small drift.

Rollback is bounded by the time it takes for fixup to converge back to the
**old** topology, which is typically symmetric to the original fixup
duration. Plan the maintenance window assuming a full rollback is
possible.

### 4.3 Point of no return

There is no true point of no return for a pure rename or reassignment as
long as the snapshot from 3.1 exists. **However**, going from single-site
to multisite changes the way new buckets are created from the moment the
manager is restarted with `multisite = true` and a non-trivial
`site_replication_factor`. Rolling back from that variant is still
possible but will trigger another fixup cycle to merge per-site copies
back into the single-site layout — plan accordingly.

## 5. Validation plan

The validation plan must check the **state after fixup has settled**, not
the state immediately after the last peer restart.

### 5.1 Cluster health

1. `splunk show cluster-status` reports `Cluster status: Ready` and every
   peer shows the expected `Site` value.
2. `splunk list cluster-config` shows the new `available_sites`, RF and SF
   values.
3. No bucket appears in `splunk list excess-buckets` for longer than the
   normal background level seen pre-change.

### 5.2 Replication and search factors

1. `Replication Factor met` and `Search Factor met` for **all** indexes.
2. Bucket counts per site, queried on the manager, match the expected
   distribution given the new RF/SF.
3. Run a sample search that you know targets data from the reassigned
   indexer(s) and confirm results are complete (compared against an
   equivalent pre-change query if you preserved one).

### 5.3 Ingest path

1. A test event sent through a forwarder reaches the cluster and lands on
   a peer whose `site` matches the routing expectation.
2. Forwarders using indexer discovery report a healthy list of peers
   (`splunk list deploy-clients` or equivalent monitoring).

### 5.4 Search path

1. Saved searches and dashboards that historically run within a known
   duration still complete in a comparable time (no order-of-magnitude
   regression).
2. If search affinity was changed: confirm by inspecting the
   `_internal` index that searches dispatched after the change actually
   hit the expected peers.

### 5.5 Sign-off criteria

The change is considered successful when, simultaneously:

- All peers are `Up` with their new site labels.
- RF and SF are met for all indexes.
- No persistent fixup activity remains.
- A representative sample of searches returns complete results.

## 6. Open reservations

The following items must be clarified against the **specific target
deployment** before this plan can be executed. They exist because this
fiche is intentionally generic.

1. **Splunk version**. Cluster behavior, terminology
   (`master`/`manager`) and CLI commands have changed across versions.
   Confirm the change plan commands and configuration keys against the
   official documentation for the deployed version.
2. **Variant of the change**. Is this a rename, a reassignment, or a
   single-site-to-multisite migration? Each variant changes which steps
   in section 3 are mandatory and the size of the fixup cycle.
3. **Current `available_sites`, RF and SF values**. The change plan must
   keep RF and SF achievable at every point in time during the rolling
   restart; with too few peers per site, removing a peer from a site
   temporarily can violate `site_replication_factor`.
4. **Cluster size and bucket count**. Drives the expected fixup duration
   and the required maintenance window length.
5. **Inter-site bandwidth and latency**. Site-aware replication will move
   data across links you may not have characterized. Confirm the link
   budget supports the fixup volume.
6. **Search head topology**. Standalone SH, SH cluster, SHs participating
   in `site_search_affinity` — each case affects section 3.4 differently,
   and SHC captaincy must be preserved.
7. **Forwarder configuration**. Whether forwarders use indexer
   discovery, static `[tcpout]` server lists, or `site_failover` changes
   how the change is perceived by data sources.
8. **Authentication context**. Every CLI command above uses
   `-auth <admin>:<password>`; the real procedure should use the
   authentication mechanism in force (SSO, REST token, mTLS) and **must
   not** leave credentials in logs or shell history.
9. **Monitoring and alerting**. The fixup cycle will fire alerts on
   cluster health, RF/SF, and per-host I/O. Pre-arrange suppression or
   silence windows to avoid drowning operators in expected noise.
10. **Backups and snapshots**. Confirm whether per-peer filesystem
    snapshots can be taken before the change as an additional safety net,
    in case `server.conf` rollback is not enough.
11. **Operational window and approvals**. This fiche does not cover
    change-advisory-board approval, communication to stakeholders, or
    coordination with downstream consumers — these are part of the
    organization's change governance process, not the technical plan.
12. **Naming convention for site labels**. `<new_site>` must follow whatever
    convention the cluster manager already enforces (length, charset, lower
    case). Mismatched casing has been observed to produce subtle issues.

## References

- Splunk Docs — Multisite indexer cluster deployment overview:
  <https://docs.splunk.com/Documentation/Splunk/latest/Indexer/Multisitearchitecture>
- Splunk Docs — Configure multisite indexer clusters:
  <https://docs.splunk.com/Documentation/Splunk/latest/Indexer/Configuremultisiteindexercluster>
- Splunk Docs — Take the cluster manager offline and put the cluster in
  maintenance mode:
  <https://docs.splunk.com/Documentation/Splunk/latest/Indexer/Usemaintenancemode>
- See also: [ITIL change governance](../methodologies/itil-gouvernance-changement.md)
  for the surrounding change-management process.
