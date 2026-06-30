# Splunk — attach one search head (cluster) to additional indexer clusters

Change plan for **adding indexer clusters to the search scope of a single,
already-running search head cluster (SHC)** — the *multi-cluster search*
topology. Starting state: one SHC already searches **one** indexer cluster. End
state: the **same** SHC (same members, same captain, same SHC role — unchanged)
also searches **N additional, already-built** indexer clusters, each via its own
cluster manager (CM), with **distributed search groups** so a search can be
scoped to a single cluster's peers (`splunk_server_group`).

> **Scope.** This attaches **more indexer clusters to one existing SHC**. It is
> **not** about adding search heads, and **not** about building or expanding the
> indexer clusters — they already exist and are healthy. The SHC's own
> coordination (`[shclustering]`, captain, deployer) does **not** change; what
> changes is the `[clustering]` block in **each member's** `server.conf`, which is
> refactored from the single-manager form into the **multi-manager** form (the
> existing cluster becomes one named manager stanza, the new ones are appended).

> **Authentication.** CLI / config examples use placeholders for readability.
> Each cluster has its **own** `pass4SymmKey`; **never** leave any secret in
> `argv`, logs or shell history — feed them on stdin from your secret store.

## 1. Background — what multi-cluster search changes

A search head joins one indexer cluster with a `[clustering]` stanza
(`mode = searchhead`, a `manager_uri`, the cluster's `pass4SymmKey`); it then
gets that cluster's peer list and generation id from the CM. To search **several**
clusters, the single `manager_uri` URL is replaced by a **list of named manager
references**, and each reference gets its own `[clustermanager:<name>]` stanza
carrying that cluster's URI and secret. The search head then aggregates the peer
lists from **all** listed CMs.

Two consequences shape the whole plan:

1. **The existing cluster's integration is refactored, not left alone.** Its
   secret moves out of `[clustering] pass4SymmKey` into
   `[clustermanager:<existing>] pass4SymmKey`, and the top-level `manager_uri`
   changes from a URL to a stanza-reference list. The **value** of the existing
   secret is unchanged — only its location. Getting this relocation wrong is the
   way you break the *currently working* cluster.
2. **One secret per cluster.** Each `[clustermanager:<name>]` carries the
   `pass4SymmKey` of **its** cluster. These are independent. The SHC's own
   `[shclustering] pass4SymmKey` is a different secret again and is **not**
   touched.

The cost is paid on **all** clusters' peers: each SHC member now pushes its
**knowledge bundle** to every peer of **every** attached cluster, so total bundle
traffic and peer disk scale with the number of clusters (see §3).

### 1.1 Preconditions

1. **All clusters healthy.** On each CM (existing + the two new):
   `splunk show cluster-status` → `Indexing Ready`, peers `Up`, RF/SF met.
2. **SHC healthy.** `splunk show shcluster-status` → captain elected, members
   converged. Record the current member list and captain (rollback baseline).
3. **Existing search works.** Capture a baseline search against the existing
   cluster and the current peer list seen by the SHC
   (`| rest /services/search/distributed/peers`).
4. **Connectivity & trust.** Every SHC member can reach each **new** CM's
   management port (`8089`); clocks in sync (NTP); TLS/CA trust to the new peers
   in place if mutual TLS is enforced.
5. **Secrets in hand (from the store, never typed inline):** the existing
   cluster's `pass4SymmKey` (to relocate, value unchanged) and **each** new
   cluster's `pass4SymmKey`.
6. **Multisite?** For each cluster that is multisite, decide the SHC's `site`
   (`site0` = search affinity off). If the SHC sits on the **same** site label in
   every cluster, `site` goes once under `[general]`; the `multisite` flag goes
   under each `[clustermanager:<name>]`. Confirm before editing.
7. **Index-name overlap check.** List the index names of all three clusters. Any
   index name present in **more than one** cluster will have its results
   **merged** at search time (see §3 / §6). Decide how that is handled before you
   widen the scope.
8. **Snapshot for rollback** (persist off-node), per SHC member:
   ```bash
   splunk btool server list clustering --debug      # the current single-manager [clustering] block
   splunk btool server list shclustering --debug     # the SHC key — do NOT alter
   splunk list cluster-config -auth <admin>:<password>
   ```

## 2. Change plan

The `[clustering]` block is **per-member instance config** in
`$SPLUNK_HOME/etc/system/local/server.conf` — set it on each member directly (or
via config management), **not** through the deployer. The **search-group
definitions** are ordinary search-head config and **are** pushed from the
deployer so they stay identical across members.

`$CONF = $SPLUNK_HOME/etc/system/local/server.conf` on the member being edited.

#### Step overview

| # | Node | What changes | Stanza / file | Action |
|---|------|--------------|---------------|--------|
| 1 | **Each SHC member** (one at a time) | refactor to multi-manager: keep existing cluster as a named stanza, append the 2 new clusters | `server.conf [clustering]` + `[clustermanager:*]` (+ `[general] site` if multisite) | edit → restart that member → wait rejoin |
| 2 | **SHC deployer** | push per-cluster distributed search groups | `distsearch.conf [distributedSearch:<group>]` in a deployer app | `apply shcluster-bundle` (may roll-restart) |
| 3 | **Each new CM** | confirm the SHC members registered | — (read-only) | `splunk list searchheads` |
| 4 | **Any SHC member** | confirm all clusters' peers + per-group targeting | — (read-only) | `rest …/distributed/peers`, scoped searches |

Only ever change the lines shown. See the secret note before starting.

> **Editing config safely + auth.** `server.conf` holds **several** secrets
> (`[shclustering]` + one per `[clustermanager:*]`). **Change only the lines
> shown; never rewrite a stanza wholesale.** When you move the existing cluster's
> key into `[clustermanager:<existing>]`, copy the **same value** — do not
> regenerate it. Apply with a targeted edit or your config-management tool; if you
> use a CLI helper, feed `pass4SymmKey`/credentials on stdin, never in `argv`.

**Step 1 — Refactor each member to the multi-manager form, one member at a
time.** Edit, restart that member, confirm it rejoins the SHC and re-registers
with **all** CMs, then move to the next. This manual rolling restart keeps the SHC
searchable throughout. Target — `$CONF` on **each member**:
```ini
[clustering]
mode = searchhead                                          ; unchanged
manager_uri = clustermanager:existing,clustermanager:two,clustermanager:three
                                                            ; CHANGED — was a single https://… URL
; pass4SymmKey                                              ; REMOVED here — moves into [clustermanager:existing] below

[clustermanager:existing]
manager_uri = https://<cm-existing>:8089                    ; ADDED — same CM as before
pass4SymmKey = <cluster_existing_pass4SymmKey>              ; ADDED — SAME value as the old [clustering] key (relocated, not changed)
multisite = true                                            ; ADDED — only if this cluster is multisite

[clustermanager:two]
manager_uri = https://<cm-2>:8089                           ; ADDED — first new cluster
pass4SymmKey = <cluster_2_pass4SymmKey>                     ; ADDED — cluster 2's OWN key
multisite = true                                            ; ADDED — only if cluster 2 is multisite

[clustermanager:three]
manager_uri = https://<cm-3>:8089                           ; ADDED — second new cluster
pass4SymmKey = <cluster_3_pass4SymmKey>                     ; ADDED — cluster 3's OWN key
multisite = true                                            ; ADDED — only if cluster 3 is multisite

[general]
site = site0                                                ; ADDED — only if multisite; site0 = affinity off (or siteN, same label across clusters)

[shclustering]
pass4SymmKey = <shc_pass4SymmKey>                           ; unchanged — the SHC's OWN key; do NOT touch
```
After each member restarts, confirm it rejoined (`splunk show shcluster-status`)
and registered with every CM (step 3) before restarting the next member.

**Step 2 — Push per-cluster search groups from the deployer.** All peers of all
clusters are searched **by default**; a named group lets a search target one
cluster's peers via `splunk_server_group`. Place the definitions in a deployer
app:
```ini
# etc/shcluster/apps/<group-app>/local/distsearch.conf  (on the SHC deployer)
[distributedSearch:<cluster_two_group>]
servers = <c2-peer-01>:8089,<c2-peer-02>:8089               ; peers of cluster 2

[distributedSearch:<cluster_three_group>]
servers = <c3-peer-01>:8089,<c3-peer-02>:8089               ; peers of cluster 3
```
Then on the deployer:
```bash
splunk apply shcluster-bundle -target https://<one-shc-member>:8089 -auth <admin>:<password>
```
> **Caveat — clustered peers are dynamic (read §6 reservation 2 first).** A
> group's `servers = …` list is static, but each CM adds/removes peers over time.
> Pinning clustered peers into a named group by hostname is brittle — a peer
> rebuilt under a new name silently drops out. Confirm the grouping strategy
> (naming convention / automation) before relying on it for scoping.

**Step 3 — Confirm registration on each new CM.** On each **new** CM:
```bash
splunk list searchheads -auth <admin>:<password>
```
Every SHC member should appear, `Connected`. A member missing on one CM almost
always means that cluster's `pass4SymmKey` is wrong in its `[clustermanager:*]`
stanza, or `8089` is blocked to that CM — **and it should not affect the other
clusters**, which is the property to verify next.

**Step 4 — Confirm aggregated peers and per-group scoping.** On any member:
```spl
| rest /services/search/distributed/peers | table peerName, status, isHealthy
```
Expect the union of all three clusters' peers, healthy. Then verify default
(all-cluster) search and per-cluster scoping:
```spl
index=_internal | stats count by splunk_server                       ; spans all clusters
index=_internal splunk_server_group=<cluster_two_group> | stats count by splunk_server   ; cluster 2 only
```

## 3. Risks and service interruption

- **Breaking the *existing* cluster during the refactor.** Relocating the
  existing key into `[clustermanager:<existing>]` with a wrong/blank value, or
  mistyping the `manager_uri` list, drops the already-working cluster. Mitigation:
  copy the exact existing key value; validate with `btool` before restart; restart
  one member at a time and confirm the existing cluster's peers still answer
  before touching the next member.
- **`pass4SymmKey` per cluster.** Each `[clustermanager:*]` needs **its** cluster's
  key. A wrong key rejects that one cluster only (peers absent for it) — verify
  isolation: the other clusters must keep working.
- **Overlapping index names across clusters.** If the same index name exists in
  two clusters, a default search returns the **union** and results merge — easy to
  misread as duplicates or inflated counts. Use `splunk_server` / search groups to
  attribute or scope. Decide policy up front (§6).
- **Knowledge-bundle load multiplies across clusters.** The SHC now replicates its
  bundle to every peer of every cluster — more bundle traffic and peer disk
  cluster-wide. Check `maxBundleSize` / `max_content_length`, replication mode
  (classic / cascading / mounted), and peer disk before, not after.
- **Per-member rolling-restart window.** During step 1/2 the SHC runs with one
  member down at a time → briefly reduced search capacity on the SHC. **No
  indexing interruption** on any cluster; the new clusters' ingest is untouched.
- **Multisite / affinity per cluster.** A wrong `site`, or assuming the same site
  label exists in every cluster when it does not, changes which peers answer and
  can add cold-cache latency or unbalance load.
- **Version skew.** The search head should be at a version ≥ the peers' in **each**
  cluster; mixed versions can degrade or block search for that cluster.

**Service interruption:** none for indexing on any cluster; for search, only a
transient, self-healing capacity reduction on the SHC during its own rolling
restart. The existing cluster's searchability must be preserved throughout (verify
per member in step 1).

## 4. Rollback

**Decision criteria** — roll back if attaching the new clusters destabilises the
SHC, if the *existing* cluster's searches regress, or if a new cluster cannot be
made to register without a config change beyond a trivial secret/typo fix. Rolling
back a single new cluster (leaving the other attached) is also valid — just drop
that one `[clustermanager:*]` stanza and its reference.

Rollback is the reverse of §2, per member, one at a time:

| # | Node | What changes | Stanza / file | Action |
|---|------|--------------|---------------|--------|
| R1 | **SHC deployer** | remove the search-group app | `distsearch.conf` app | delete app → `apply shcluster-bundle` |
| R2 | **Each member** (one at a time) | revert `[clustering]` to the single-manager form (existing cluster only) | `server.conf [clustering]` + drop `[clustermanager:*]` | edit/restore → restart → wait rejoin |
| R3 | **CMs** | confirm new CMs no longer list the members; existing CM still does | — (read-only) | `splunk list searchheads` |

Target — `$CONF` on **each member** for R2 (back to the pre-change form):
```ini
[clustering]
mode = searchhead
manager_uri = https://<cm-existing>:8089                    ; RESTORED single URL
pass4SymmKey = <cluster_existing_pass4SymmKey>              ; RESTORED here (same value)
; [clustermanager:existing|two|three]                       ; REMOVED — delete all three stanzas
[shclustering]
pass4SymmKey = <shc_pass4SymmKey>                           ; unchanged — never touched
```
Restoring each member's `server.conf` from the §1.1 snapshot and restarting
achieves the same end state. **Point of no return:** none — no data moves; the
existing cluster connection is restored by reverting config.

## 5. Validation plan

1. **Registration.** Each new CM's `splunk list searchheads` lists all SHC
   members `Connected`; the existing CM still lists them.
2. **Aggregated peers.** On a member, `| rest …/distributed/peers` returns the
   union of all clusters' peers, healthy.
3. **Per-cluster scoping.** A `splunk_server_group=<group>` search returns exactly
   one cluster's peers; a default search spans all.
4. **Existing cluster unaffected.** The §1.1 baseline search against the existing
   cluster returns the same results in comparable time.
5. **Index-overlap behaviour matches the decided policy** (merged vs scoped).
6. **Bundle replication healthy** across all clusters' peers (no oversized-bundle
   / `bundle replication failed` errors;
   `index=_internal component=DistributedBundleReplicationManager log_level=ERROR`).

**Sign-off** = all members `Connected` on every CM, peers from all clusters
searchable and scopable per group, the pre-existing cluster unaffected, and bundle
replication clean.

## 6. Open reservations

1. **Default scope vs per-cluster scope.** Decide whether everyday searches should
   span **all** clusters (default) or be scoped per cluster via search groups, and
   set user/app defaults accordingly.
2. **Static groups vs dynamic clustered peers.** Named-group `servers` lists are
   static; CMs manage peer membership dynamically. Define how group membership
   stays correct across peer rebuilds (naming convention, automation) before
   relying on it.
3. **Index-name collisions across clusters.** Confirm which index names exist in
   more than one cluster and the intended behaviour (merge vs attribute via
   `splunk_server` vs scope via group). This is the most common multi-cluster
   surprise.
4. **Secrets.** Confirm each cluster's `pass4SymmKey` and that the existing key is
   **relocated unchanged**; confirm the SHC `[shclustering]` key is preserved.
5. **Multisite & affinity per cluster.** Confirm the `site` value is valid in
   **every** multisite cluster and that the same-site assumption holds; otherwise
   place `site`/`multisite` per the Splunk multi-cluster multisite rules.
6. **Bundle-replication scaling.** Re-check `maxBundleSize` / `max_content_length`,
   replication mode and peer disk for the **new total peer count** across clusters.
7. **Version compatibility.** Search head version ≥ peer version in each cluster.
8. **CM redundancy.** If any cluster uses cluster-manager redundancy, the
   `[clustermanager:*]` stanza for it must reference the redundancy setup, not a
   single CM — handle separately.
9. **Auth, TLS, time sync** across all members and all new CMs/peers.
10. **Change governance.** CAB approval, comms and consumer coordination belong to
    the change-management process, not this technical plan.

## 7. References

- Splunk Docs — Search across multiple indexer clusters (the core mechanism):
  <https://help.splunk.com/en/data-management/manage-splunk-enterprise-indexers/10.4/configure-the-search-head/search-across-multiple-indexer-clusters>
- Splunk Docs — Configure multi-cluster search (server.conf form):
  <https://docs.splunk.com/Documentation/Splunk/9.4.2/Indexer/Configuremulti-clustersearch>
- Splunk Docs — Integrate the search head cluster with an indexer cluster:
  <https://docs.splunk.com/Documentation/Splunk/9.4.1/DistSearch/SHCandindexercluster>
- Splunk Docs — Create distributed search groups:
  <https://docs.splunk.com/Documentation/Splunk/latest/DistSearch/Distributedsearchgroups>
- Splunk Docs — How search works in an indexer cluster:
  <https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Howclusteredsearchworks>
- See also: the [SHC knowledge-bundle handbook](../handbooks/splunk-shc-knowledge-bundle/00-foundations.md)
  for the three-bundles lexicon, and
  [ITIL change governance](../methodologies/itil-gouvernance-changement.md) for the
  surrounding change-management process.
