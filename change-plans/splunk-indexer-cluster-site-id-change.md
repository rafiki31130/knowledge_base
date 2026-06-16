# Splunk indexer cluster — site id change

Generic change plan template for changing the `site` attribute of one or
more members of a Splunk indexer cluster. Treat this fiche as a
**template**: every value in angle brackets must be confirmed against the
target deployment, and the variant of the change must be matched to the
correct **official Splunk procedure** before execution.

> **Important.** There is no single official procedure for "changing a site
> id". Splunk documents distinct procedures for distinct variants. The
> wrong assumption — that you only need to edit `[general] site` in
> `server.conf` and restart — is **explicitly contradicted** by Splunk for
> the peer-move case (see §6, reservation 1). Identify the variant first,
> then follow the matching official procedure.

## 1. Generic description of the change

In a Splunk indexer cluster, each member (cluster manager, peer, search
head) declares which **site** it belongs to via the `site` attribute in
`server.conf` (`[general] site = <siteX>`). The cluster manager uses these
site labels together with `site_replication_factor` and
`site_search_factor` to decide where bucket copies live and which copies
are searchable.

A "site id change" covers three distinct variants, which have **different**
official procedures:

- **Variant A — Move a peer to a new site.** A peer that used to belong to
  `<site_a>` becomes part of `<site_b>` (e.g. physical relocation, mistake
  during initial deployment caught after data has accumulated). Official
  procedure: *Move a peer to a new site* — see §6 reservation 1.
- **Variant B — Migrate single-site to multisite.** The cluster, currently
  `multisite = false`, is reconfigured as a multisite cluster with
  `available_sites = <site1>,<site2>,…`. Official procedure: *Migrate an
  indexer cluster from single-site to multisite* — see §6 reservation 2.
- **Variant C — Rename a site label.** The cluster keeps its topology but
  the label `<old_site>` becomes `<new_site>` across the manager and the
  peers that carry it. Splunk does **not** publish a dedicated procedure
  for this variant; it must be built from the multisite configuration
  pages (see §6 reservation 3) and treated with extra care.

All three variants touch `server.conf` on the cluster manager
(`[clustering] available_sites`, `site_replication_factor`,
`site_search_factor`, and possibly `multisite`), and on every affected
indexer (`[general] site`) and search head (`[general] site` when
site-based search affinity is in use). They also affect forwarder
configurations using `indexerDiscovery` or `site_failover` when present.

The goal of the change is to make the cluster's site topology reflect a
new operational reality without data loss, and with bucket counts
converging back to the configured replication and search factors after the
change.

## 2. Risks and service interruption

### Risks

- **Stranded bucket copies** (Variant A specifically). If a peer is
  reassigned by editing `server.conf` instead of following the official
  offline-and-reprovision procedure, its existing local bucket copies stay
  on the peer but are accounted for under the new site. The cluster
  manager does **not** automatically rebalance them. Replication and
  search factors become inconsistent in ways that are hard to recover
  from.
- **Bucket fixup storm**. Any site change triggers the manager to
  re-evaluate per-site bucket placement. The cluster will start a fixup
  cycle that can move and replicate large volumes of data. Network and
  disk I/O on indexers will spike.
- **Replication / Search factor violations**. Until fixup completes, the
  cluster reports `Replication Factor not met` and `Search Factor not
  met`. Some buckets may briefly be searchable from fewer sites than
  intended.
- **Search affinity disruption**. If `site_search_affinity = true`,
  queries may suddenly hit a different set of indexers after the change,
  with cold-cache search latency.
- **Misalignment between manager and peers**. `available_sites` on the
  manager must list every site label declared by peers; otherwise affected
  peers will be rejected from the cluster.
- **Forwarder routing breakage**. Forwarders using site-aware indexer
  discovery may stop routing correctly until they pick up the new manager
  view.
- **Inconsistent `server.conf`**. A typo in `site = …` will prevent the
  peer from rejoining; rollback may be needed before fixup even starts.

### Service interruption

- **Ingest**: usually no full outage. Forwarders with autoLB keep sending
  data; expect transient backoffs while affected peers restart.
- **Search**: short interruption when the manager re-evaluates the
  generation. Dashboards may show partial results around each peer
  restart.
- **Cluster availability**: degraded (yellow) state for the entire fixup
  duration; not an outage, but cluster-health alerting will fire.
- **Estimated duration**: peer restart is seconds; fixup is a function of
  total bucket count, RF/SF, and inter-peer bandwidth — minutes for a
  small cluster, hours for a large one. **Variant A's official procedure
  requires wiping the peer's index database** (see §6 reservation 1),
  which means the peer rebuilds its bucket copies from other peers — plan
  the window against the full re-replication, not against a simple
  restart.

## 3. Change plan

The exact sequence depends on the variant. Pick the matching official
procedure (linked in §6) and follow it. The skeleton below highlights what
is common.

### 3.1 Pre-change (all variants)

1. **Snapshot the current topology** for the rollback plan:
   ```bash
   splunk show cluster-status -auth <admin>:<password>
   splunk list cluster-config -auth <admin>:<password>
   splunk btool server list clustering --debug
   splunk btool server list general --debug
   ```
   Persist this output outside the cluster nodes.
2. **Capture bucket health baseline**: number of buckets, RF/SF status,
   list of buckets currently in fixup.
3. **Confirm cluster manager is healthy** (no recurring fixup errors in
   `splunkd.log`).
4. **Pause ingestion-sensitive jobs** for the maintenance window.
5. **Enable maintenance mode** on the cluster manager to suppress fixup
   while you reconfigure:
   ```bash
   splunk enable maintenance-mode -auth <admin>:<password>
   splunk show maintenance-mode -auth <admin>:<password>   # confirm
   ```

### 3.2 Variant A — Move a peer to a new site

Follow the official procedure (§6 reservation 1) **literally**. Summary:

1. **Take the peer offline** with `splunk offline` so the manager
   reassigns its bucket copies to other peers in its current site **before**
   the peer leaves.
2. Wait for the manager to confirm the reassignment is complete.
3. (Physical relocation if applicable.)
4. **Delete the entire Splunk Enterprise installation on the peer**,
   including its index database with all bucket copies.
5. **Reinstall Splunk Enterprise**, re-enable clustering, set
   `[general] site = <new_site>`.
6. Confirm the peer rejoins the cluster:
   ```bash
   splunk show cluster-status -auth <admin>:<password>
   ```
   The peer should appear with its new `Site` value, RF/SF re-converging
   as the manager replicates bucket copies back to it.

Repeat per affected peer, sequentially, never in parallel.

### 3.3 Variant B — Migrate single-site to multisite

Follow the official procedure (§6 reservation 2). Summary, in order:

1. **Configure the cluster manager for multisite** and restart it. Example
   shape (real values per the deployment):
   ```bash
   splunk edit cluster-config \
     -mode manager \
     -multisite true \
     -available_sites <site1>,<site2> \
     -site <site1> \
     -site_replication_factor origin:<r>,total:<R> \
     -site_search_factor      origin:<s>,total:<S>
   splunk restart
   ```
2. **Decide whether existing buckets must adhere to the new multisite RF/SF**;
   the manager has a configuration toggle for this — confirm against the
   official page.
3. **Enable maintenance mode** on the manager to avoid unnecessary fixup
   during peer reconfiguration.
4. **Configure each existing peer** for multisite, specifying its manager
   and its `site`. Restart per peer.
5. **Add new peers** if the new topology requires them.
6. **Configure each search head** for multisite, specifying its manager
   and its `site`.

### 3.4 Variant C — Rename a site label

Splunk does not publish a dedicated procedure for renaming a site label in
place. Treat this variant as a **deliberate composition** of the multisite
configuration steps (§6 reservation 3), and consider whether it can be
expressed instead as Variant A (move-a-peer) applied in sequence to the
peers carrying `<old_site>`, with `<new_site>` added to the manager's
`available_sites` first.

If a true in-place rename is required, the safe sequence is:

1. Add `<new_site>` to the manager's `available_sites` (so both labels
   coexist temporarily), restart the manager.
2. With maintenance mode enabled, edit `[general] site = <new_site>` on
   each peer carrying `<old_site>`, restart each peer in turn, wait for
   `Up`.
3. Once no peer (and no search head) still references `<old_site>`,
   remove `<old_site>` from `available_sites` and restart the manager.
4. Disable maintenance mode and let fixup converge.

This sequence is **not** an officially documented procedure — it is the
least-bad construction from the multisite configuration pages. It belongs
in the open reservations (§6) until validated against the target version.

### 3.5 Exit maintenance and fixup (all variants)

1. Disable maintenance mode:
   ```bash
   splunk disable maintenance-mode -auth <admin>:<password>
   ```
2. Watch fixup start and progress:
   ```bash
   splunk show cluster-status -auth <admin>:<password>
   splunk list excess-buckets -auth <admin>:<password>
   ```
3. Let the cluster converge before declaring the change complete.

## 4. Rollback plan

### 4.1 Decision criteria

Trigger rollback if:

- A reconfigured peer fails to rejoin the cluster and the cause is not a
  trivial typo correctable in minutes.
- The cluster reports a persistent `Replication Factor not met` that is
  not making forward progress over a sustained window.
- Search results show systematic gaps mapped to the site change (not just
  transient cold-cache latency).
- The cluster manager itself becomes unstable after its own restart.

### 4.2 Rollback steps

The reversibility cost depends on the variant.

- **Variant A — Move a peer**. There is no symmetric "un-offline + un-wipe"
  rollback once step 4 of §3.2 has run on the peer. Rollback before step 4
  means re-enabling the peer in its original site (its bucket copies are
  still local). Rollback after step 4 means reprovisioning the peer with
  `<old_site>` — the data has been redistributed across the original site
  and will replicate back. Plan the window accordingly.
- **Variant B — Migrate to multisite**. Rolling back to single-site
  requires restoring `multisite = false` and the original `[clustering]`
  block on the manager (restart), and restoring `[general] site` on every
  peer and search head (restart each). The cluster then re-converges to
  the single-site bucket layout, which is another fixup cycle.
- **Variant C — Rename**. Symmetric: re-add `<old_site>` to
  `available_sites`, revert each peer's `[general] site`, then drop
  `<new_site>` if no member references it.

Common reversal steps:

1. Re-enable maintenance mode on the cluster manager.
2. Restore the previous `server.conf` files from the snapshot taken in
   §3.1, restart the corresponding `splunkd` instances.
3. Disable maintenance mode and let the cluster converge.
4. Compare `cluster-status` and bucket counts against the pre-change
   snapshot.

### 4.3 Point of no return

- Variant A: deleting the index database of a peer (step 4 of §3.2) is
  the operational point of no return for that peer's local data — the
  cluster still owns the data through replicated copies on other peers,
  but the local copy is gone.
- Variant B: enabling `multisite = true` on the manager is the conceptual
  point of no return; from that moment, new buckets are created with the
  multisite RF/SF policy. Reverting is still possible but triggers
  another fixup cycle.
- Variant C: removing `<old_site>` from `available_sites` is the point
  where any member still labelled `<old_site>` is rejected.

## 5. Validation plan

The validation plan must check the **state after fixup has settled**.

### 5.1 Cluster health

1. `splunk show cluster-status` reports `Cluster status: Ready` and every
   peer shows the expected `Site` value.
2. `splunk list cluster-config` shows the expected `available_sites`, RF
   and SF values.
3. No bucket remains in `splunk list excess-buckets` longer than the
   normal background level seen pre-change.

### 5.2 Replication and search factors

1. `Replication Factor met` and `Search Factor met` for **all** indexes.
2. Bucket counts per site match the expected distribution given the new
   RF/SF.
3. A sample search known to target data from the reassigned indexer(s)
   returns complete results.

### 5.3 Ingest path

1. A test event sent through a forwarder reaches the cluster and lands on
   a peer whose `site` matches the routing expectation.
2. Forwarders using indexer discovery report a healthy list of peers.

### 5.4 Search path

1. Saved searches and dashboards complete in a comparable time to the
   pre-change baseline.
2. If search affinity was changed: confirm via `_internal` that searches
   dispatched after the change hit the expected peers.

### 5.5 Sign-off criteria

The change is successful when, simultaneously:

- All peers are `Up` with their new site labels.
- RF and SF are met for all indexes.
- No persistent fixup activity remains.
- A representative sample of searches returns complete results.

## 6. Open reservations

These items **must** be clarified against the specific target deployment
before this plan can be executed. They exist because this fiche is
intentionally generic.

1. **Variant A — official procedure**. Confirm the exact steps for the
   deployed Splunk version against the official page:
   [Move a peer to a new site (Splunk Docs)](https://help.splunk.com/en/splunk-enterprise/administer/manage-indexers-and-indexer-clusters/9.0/manage-a-multisite-indexer-cluster/move-a-peer-to-a-new-site).
   The official procedure requires `splunk offline` then **deleting the
   entire Splunk installation including the index database** before
   reinstalling with the new `site` — a plain `server.conf` edit + restart
   is explicitly insufficient.
2. **Variant B — official procedure**. Confirm against the official page:
   [Migrate an indexer cluster from single-site to multisite (Splunk Docs)](https://help.splunk.com/en/data-management/manage-splunk-enterprise-indexers/10.2/deploy-and-configure-a-multisite-indexer-cluster/migrate-an-indexer-cluster-from-single-site-to-multisite).
   Verify the toggle that forces existing buckets to adhere to the new
   multisite RF/SF.
3. **Variant C — no official procedure**. Splunk does not publish a
   dedicated "rename a site" procedure. The sequence proposed in §3.4 is
   constructed from the multisite configuration pages and is **not**
   officially blessed. Validate it on a non-production cluster of similar
   shape, or seek confirmation from Splunk support before applying it to
   production.
4. **Splunk version**. Cluster behaviour, terminology
   (`master`/`manager`) and CLI shape changed across versions. Match the
   procedure page to the version actually deployed.
5. **Variant identification**. Before anything else, confirm which of
   A / B / C is being executed. The risks, the rollback cost and the
   point of no return are very different.
6. **Current `available_sites`, RF and SF values**. The change must keep
   RF and SF achievable at every point in time during the rolling
   restart; with too few peers per site, taking one offline can violate
   `site_replication_factor`.
7. **Cluster size and bucket count**. Drives the expected fixup duration
   and the maintenance window length. Variant A's wipe-and-rejoin can
   move significant data across the cluster.
8. **Inter-site bandwidth and latency**. Site-aware replication moves
   data across links you may not have characterized. Confirm the link
   budget supports the fixup volume.
9. **Search head topology**. Standalone SH, SH cluster, SHs participating
   in `site_search_affinity` — each case affects search-head
   reconfiguration differently, and SHC captaincy must be preserved.
10. **Forwarder configuration**. Whether forwarders use indexer discovery,
    static `[tcpout]` server lists, or `site_failover` changes how the
    change is perceived by data sources.
11. **Authentication context**. Every CLI command above uses
    `-auth <admin>:<password>` for clarity. The real procedure should use
    the authentication mechanism in force (SSO, REST token, mTLS) and
    must not leave credentials in logs or shell history.
12. **Monitoring and alerting**. The fixup cycle will fire alerts on
    cluster health, RF/SF, and per-host I/O. Pre-arrange suppression
    windows.
13. **Backups and snapshots**. Confirm whether per-peer filesystem
    snapshots can be taken before the change as an additional safety net.
14. **Operational window and approvals**. Change-advisory-board approval,
    stakeholder communication, downstream-consumer coordination belong to
    the change governance process, not this technical plan.
15. **Naming convention for site labels**. `<new_site>` must follow
    whatever convention the cluster manager already enforces (length,
    charset, lower case).

## References

- Splunk Docs — Move a peer to a new site:
  <https://help.splunk.com/en/splunk-enterprise/administer/manage-indexers-and-indexer-clusters/9.0/manage-a-multisite-indexer-cluster/move-a-peer-to-a-new-site>
- Splunk Docs — Migrate an indexer cluster from single-site to multisite:
  <https://help.splunk.com/en/data-management/manage-splunk-enterprise-indexers/10.2/deploy-and-configure-a-multisite-indexer-cluster/migrate-an-indexer-cluster-from-single-site-to-multisite>
- Splunk Docs — Multisite indexer cluster architecture:
  <https://docs.splunk.com/Documentation/Splunk/9.4.1/Indexer/Multisitearchitecture>
- Splunk Docs — Use maintenance mode:
  <https://docs.splunk.com/Documentation/Splunk/latest/Indexer/Usemaintenancemode>
- See also: [ITIL change governance](../methodologies/itil-gouvernance-changement.md)
  for the surrounding change-management process.
