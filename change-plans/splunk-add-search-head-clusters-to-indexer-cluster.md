# Splunk — attach additional search head clusters to an existing indexer cluster

Change plan for **adding one or more already-built search head clusters (SHCs)
as extra search tiers of an existing indexer cluster**, when one SHC is already
attached and serving search against that cluster. The end state: several SHCs,
each independent for its own coordination, **all** searching the **same** set of
clustered peers, with each SHC keeping its **distributed search groups**
(`distsearch.conf` `[distributedSearch:<group>]`, targeted in SPL via
`splunk_server_group`).

> **Scope.** This is about *attaching the search tier* — registering the members
> of additional SHCs as search heads of an indexer cluster that already exists
> and is already healthy. **Out of scope:** building an SHC from scratch
> (captain election, deployer bring-up), building/expanding the indexer cluster
> itself, and migrating buckets. Each SHC is assumed already operational
> (captain elected, deployer in place, members replicating their SHC config).

> **Terminology — "search groups".** Here this means **distributed search
> groups**: named subsets of search peers declared in `distsearch.conf`
> (`[distributedSearch:<group>]`, `servers = …`) and targeted at search time with
> `splunk_server_group=<group>`. It is **not** the same thing as *multi-cluster
> search* (one SHC pointing at several cluster managers via a `manager_uri`
> list); that is a distinct operation, sketched as a variant in §2 and flagged in
> §6. Confirm which you mean before running this plan.

> **Authentication.** CLI examples use `-auth <admin>:<password>` and
> `-secret <key>` for readability only. Use the auth mechanism in force and
> **never leave secrets in `argv`, logs or shell history** — feed them on stdin
> from your secret store. The cluster secrets in particular (`pass4SymmKey`) must
> never be echoed.

## 1. Background — what "attaching an SHC to an indexer cluster" actually changes

Each member of an SHC becomes a **search head of the indexer cluster** by setting
a `[clustering]` stanza in its `server.conf` with `mode = searchhead`, the
cluster manager URI, and the **indexer cluster's** `pass4SymmKey`. From then on
that member gets its **peer list and generation id from the cluster manager (CM)**
instead of a static `[distributedSearch] servers` list — the clustered peers are
**auto-discovered**, not hand-listed.

Two secrets coexist and are constantly confused — getting them wrong is the
single most common failure of this change:

| Secret | Stanza | Shared by | Role |
|---|---|---|---|
| **Indexer-cluster key** | `[clustering] pass4SymmKey` | **every** SHC member of **every** SHC **and** the CM/peers | lets a search head register with the CM |
| **SHC key** | `[shclustering] pass4SymmKey` | only the members **within one** SHC | coordinates that SHC (captain, conf replication) |

So: all three SHCs share the **same** `[clustering]` key (the indexer cluster's);
each SHC keeps its **own, distinct** `[shclustering]` key. Adding a new SHC means
giving each of its members the indexer-cluster key under `[clustering]` while
leaving its `[shclustering]` key untouched.

Multiple SHCs against one indexer cluster is a supported topology. Each SHC's
members register independently with the CM; the CM simply sees more search heads.
The cost is paid on the **peers**: every search head pushes its **own knowledge
bundle** to **every** peer on each search cycle, so total bundle count and
replication traffic scale with the **total number of search heads**, not the
number of SHCs (see §3).

### 1.1 Preconditions

1. **Indexer cluster healthy:** `splunk show cluster-status` on the CM →
   `Indexing Ready`, all peers `Up`, RF/SF met, `No fixup tasks in progress`.
2. **Existing SHC unaffected baseline captured:** note its members, captain, and
   that `splunk list searchheads` on the CM lists exactly the current heads —
   this is the before-state you compare against.
3. **Each new SHC is already operational on its own:** captain elected
   (`splunk show shcluster-status`), deployer reachable, members converged.
4. **Connectivity & trust:** every new SHC member can reach the CM management
   port (`8089`) over the network; clocks are in sync (NTP); TLS/CA trust between
   heads and peers is in place if mutual TLS is enforced.
5. **Secrets in hand (from the secret store, never typed inline):** the indexer
   cluster `pass4SymmKey`, and confirmation that each new SHC's `[shclustering]`
   key is distinct and must be preserved.
6. **Multisite?** If the indexer cluster is multisite, decide each new SHC's
   `site` (use `site0` to **disable** search affinity, or `siteN` to bias each
   SHC to a site). Confirm before editing.
7. **Snapshot for rollback** (persist off-node), per new SHC member and the CM:
   ```bash
   splunk btool server list clustering --debug      # on each member (pre-change: no searchhead stanza)
   splunk btool server list shclustering --debug     # on each member (the SHC key — do NOT alter)
   splunk list searchheads -auth <admin>:<password>  # on the CM (baseline head list)
   ```
8. **Pre-arrange monitoring suppression / change window:** the rolling restarts
   briefly reduce search capacity **on the SHC being changed only**.

## 2. Change plan

Process **one new SHC at a time**, fully (integrate → search groups → verify),
before starting the next. This keeps blast radius to a single SHC and leaves the
already-attached SHC and the other new SHC untouched while you work.
`$CONF = $SPLUNK_HOME/etc/system/local/server.conf` on the node being edited.

The `[clustering]` integration is **per-member instance config** — set it on each
member directly (or via your config-management tool), **not** through the deployer
(the deployer pushes apps to `etc/apps/`; the cluster integration lives in
`etc/system/local/` and must not be overwritten by a bundle). The **search-group
definitions**, by contrast, are ordinary search-head config and **are** pushed
from that SHC's deployer so they stay identical across members.

#### Step overview — repeat steps 1→4 for each new SHC (`<shc-b>`, then `<shc-c>`)

| # | Node | What changes | Stanza / file | Action |
|---|------|--------------|---------------|--------|
| 1 | **Each member** of the SHC (one at a time) | add indexer-cluster integration | `server.conf [clustering]` (+ `[general] site` if multisite) | edit → restart that member → wait rejoin |
| 2 | **That SHC's deployer** | push the distributed search-group defs | `distsearch.conf [distributedSearch:<group>]` in a deployer app | `apply shcluster-bundle` (may roll-restart) |
| 3 | **CM** | confirm the new heads registered | — (read-only) | `splunk list searchheads` |
| 4 | **Any member** of the SHC | confirm clustered search + group targeting | — (read-only) | test searches |

Only ever change the lines shown below — see the secret-handling note before you
start.

> **Editing config safely + auth.** `server.conf` holds **both** `pass4SymmKey`
> values. **Change only the lines highlighted; never rewrite the `[clustering]` or
> `[shclustering]` stanza wholesale** (that would force you to re-inject a secret
> and risks cross-wiring the two keys). Apply with a targeted edit or your
> config-management tool. For the CLI equivalent of step 1
> (`splunk edit cluster-config …`), **never** pass `-secret`/`-auth` on the
> command line — feed them on stdin, e.g.
> `printf 'export SPLUNK_USERNAME=admin\nexport SPLUNK_PASSWORD=%s\n…\n' "$PW" | bash -s`,
> with `$PW`/`$KEY` read once from the secret store.

**Step 1 — Integrate each member as a search head of the indexer cluster.** Do it
**one member at a time**: edit, restart that member, wait for it to rejoin the SHC
and register with the CM, then move to the next member. This is a manual rolling
restart — at no point is the whole SHC down, so search stays available on this SHC
throughout. Target — `$CONF` on **each member**:
```ini
[clustering]
mode = searchhead                              ; ADDED
manager_uri = https://<cluster-manager>:8089    ; ADDED — the indexer cluster's CM
pass4SymmKey = <indexer_cluster_pass4SymmKey>   ; ADDED — the INDEXER CLUSTER key (NOT this SHC's key)
multisite = true                                ; ADDED — ONLY if the indexer cluster is multisite

[general]
site = site0                                    ; ADDED — ONLY if multisite; site0 = search affinity OFF (or siteN to bias)

[shclustering]
pass4SymmKey = <shcB_pass4SymmKey>              ; unchanged — this SHC's OWN key; do NOT touch
; all other [shclustering] keys                  — unchanged
```
CLI equivalent on each member (secrets via stdin, not argv):
```bash
splunk edit cluster-config -mode searchhead -manager_uri https://<cluster-manager>:8089 -secret <KEY>   # add -site siteN if multisite
splunk restart
```
After each member restarts, confirm it rejoined its SHC (`splunk show
shcluster-status`) and appears on the CM (`splunk list searchheads`) before
restarting the next.

**Step 2 — Push the distributed search groups from this SHC's deployer.** Place
the group definitions in an app under the deployer's
`$SPLUNK_HOME/etc/shcluster/apps/<group-app>/local/distsearch.conf`. Clustered
peers are auto-discovered into the implicit `default` group; named groups let SPL
target a subset via `splunk_server_group`. Target file:
```ini
# etc/shcluster/apps/<group-app>/local/distsearch.conf  (on this SHC's deployer)
[distributedSearch:<group_name>]
servers = <peer-01>:8089,<peer-02>:8089         ; peers that belong to this group
default = false                                  ; true would make it the implicit search scope
```
Then, on the deployer:
```bash
splunk apply shcluster-bundle -target https://<one-shc-member>:8089 -auth <admin>:<password>
```
This propagates via the captain to all members; it may trigger an SHC rolling
restart, which preserves search availability on the SHC by design.

> **Caveat — clustered peers are dynamic (read §6 reservation 2 first).** A named
> group's `servers = …` is a **static** list, but the CM adds/removes clustered
> peers over time. Pinning clustered peers into a named group by hostname is
> brittle: a peer rebuilt under a new name silently drops out of the group.
> Confirm whether the groups are meant to hold clustered peers at all, or only
> non-clustered (standalone) peers the SHC also searches.

**Step 3 — Confirm the new heads registered with the CM.** On the CM:
```bash
splunk list searchheads -auth <admin>:<password>
```
Expect the baseline heads **plus** every member of the new SHC, all `Connected`
/ `Up`. A member missing here almost always means a `[clustering] pass4SymmKey`
mismatch (wrong/!= indexer-cluster key) or blocked `8089`.

**Step 4 — Confirm clustered search and group targeting from the SHC.** On any
member of the new SHC:
```spl
| rest /services/search/distributed/peers | table peerName, status, isHealthy
```
All clustered peers should be present and healthy. Then validate a real search
returns clustered data, and that group targeting works:
```spl
index=_internal splunk_server_group=<group_name> | stats count by splunk_server
```
Only once this SHC is fully verified, repeat steps 1→4 for the next SHC.

### 2.1 Variant — multi-cluster search (only if that is what "search groups" meant)

If the goal is instead for each SHC to search **several indexer clusters**, the
`[clustering]` stanza takes a **list** of named manager references, one stanza
each — **not** distributed search groups:
```ini
[clustering]
manager_uri = clustermanager:one,clustermanager:two

[clustermanager:one]
manager_uri = https://<cluster-manager-1>:8089
pass4SymmKey = <cluster_1_pass4SymmKey>
multisite = true                                ; per-cluster, if applicable

[clustermanager:two]
manager_uri = https://<cluster-manager-2>:8089
pass4SymmKey = <cluster_2_pass4SymmKey>
```
Everything else (per-member edit, manual rolling restart, verification) is the
same. This variant is mutually exclusive with the single-`manager_uri` form in
step 1 — pick one. See §6 reservation 1.

## 3. Risks and service interruption

- **`pass4SymmKey` confusion (most common failure).** Putting the **SHC** key in
  `[clustering]`, or a wrong indexer-cluster key, gets the member **rejected by
  the CM** — it never receives a peer list and returns no clustered data. The
  inverse (touching `[shclustering]`) can **break the SHC itself** (member
  ejected, captain churn). Mitigation: targeted line edits only; verify with
  `btool` before restart; verify on the CM after (step 3).
- **Knowledge-bundle load scales with total search-head count.** Going from one
  SHC to three multiplies the number of heads pushing their **own** bundle to
  **every** peer. More bundles in `var/run/searchpeers/`, more replication
  traffic, more peer disk and CPU. On large bundles this can approach
  `maxBundleSize` (SH side) / `max_content_length` (peer side) and slow searches.
  Mitigation: check bundle size and replication mode (classic / cascading /
  mounted) **before** adding heads; tighten `replicationAllowlist`.
- **Added search/concurrency load on the peers.** Three SHCs issue more
  concurrent searches against the same peers — CPU, IO and search-concurrency
  limits are now shared three ways. Consider Workload Management / quotas.
- **Per-SHC rolling-restart window.** During step 1/2 the SHC being changed runs
  with one member down at a time → reduced search capacity **on that SHC only**.
  The already-attached SHC, the other new SHC, **ingest, and the indexer cluster
  are unaffected.** No indexing interruption at any point.
- **Brittle static groups over dynamic peers** (see §2 step 2 caveat / §6.2).
- **Version skew.** A search head should generally be at a version **≥** its
  peers'. Mixed SHC/peer versions can degrade or block search.
- **Multisite affinity surprises.** A wrong `site` on a new SHC changes which
  peers answer (affinity), adding cold-cache latency or unbalancing peer load.

**Service interruption:** none for indexing; none for search on the existing
SHC; only a transient, self-healing capacity reduction on each new SHC during its
own rolling restart.

## 4. Rollback

**Decision criteria** — roll back a given SHC if its members fail to register
with the CM (and it is not a trivial typo/secret fix), if attaching it visibly
degrades peer health or bundle replication for the **other** SHCs, or if the SHC
itself becomes unstable (captain churn) after the edits.

Rollback is **per SHC and per member**, the reverse of §2:

| # | Node | What changes | Stanza / file | Action |
|---|------|--------------|---------------|--------|
| R1 | **That SHC's deployer** | remove the search-group app | `distsearch.conf` app | delete app → `apply shcluster-bundle` |
| R2 | **Each member** (one at a time) | remove indexer-cluster integration | `server.conf [clustering]` (+ multisite `[general] site`) | edit/remove → restart → wait rejoin |
| R3 | **CM** | confirm the heads dropped | — (read-only) | `splunk list searchheads` |

Target — `$CONF` on **each member** for R2:
```ini
; [clustering]                                   ; REMOVED — delete the whole searchhead stanza added in step 1
; [general] site = site0                         ; REMOVED — only if added for multisite
[shclustering]
pass4SymmKey = <shcB_pass4SymmKey>              ; unchanged — never touched, never touch now
```
CLI equivalent: `splunk remove cluster-config` then `splunk restart`, one member
at a time. Restoring each member's `server.conf` from the §1.1 snapshot and
restarting achieves the same end state.

After R3 the CM should list exactly the **baseline** heads again. **Point of no
return:** none — no data is moved or wiped; detaching a search tier is fully
reversible at the cost of another rolling restart.

## 5. Validation plan

Validate per SHC, then globally:

1. **CM head registry.** `splunk list searchheads` on the CM shows the baseline
   heads **plus all** members of each newly added SHC, all `Connected`.
2. **Peer discovery per SHC.** On a member of each new SHC,
   `| rest /services/search/distributed/peers` lists **all** clustered peers,
   healthy — no static `servers` list required.
3. **Clustered search returns data.** A known search (e.g. `index=_internal …`)
   on each new SHC returns complete results from the clustered peers, in time
   comparable to the existing SHC's baseline.
4. **Search-group targeting.** `… splunk_server_group=<group_name> | stats count
   by splunk_server` returns exactly the intended peers for each defined group.
5. **Bundle replication healthy.** No `bundle replication failed` /
   oversized-bundle warnings on peers
   (`index=_internal component=DistributedBundleReplicationManager log_level=ERROR`);
   peer disk under `var/run/searchpeers/` within expectations for the new head
   count.
6. **No regression on the existing SHC.** Its searches and bundle replication are
   unchanged versus the §1.1 baseline.

**Sign-off** = all members of all SHCs `Connected` on the CM, each SHC searches
the full peer set with correct group targeting, bundle replication clean, and the
pre-existing SHC unaffected.

## 6. Open reservations

1. **Meaning of "search groups" (must confirm).** This plan assumes **distributed
   search groups** (`distsearch.conf`). If you meant **multi-cluster search**
   (each SHC searching several indexer clusters), use the §2.1 variant instead —
   the two are different changes. Do not run before confirming.
2. **Static groups vs dynamic clustered peers.** Named-group `servers` lists are
   static; clustered peers are managed by the CM and change over time. Decide
   whether groups should contain clustered peers at all, and if so how membership
   stays correct across peer rebuilds (naming convention, automation).
3. **Secrets.** Confirm the indexer-cluster `pass4SymmKey` and that **each** SHC's
   `[shclustering]` key is distinct and preserved. Never reuse the SHC key as the
   clustering key or vice versa.
4. **Multisite & search affinity.** Confirm each new SHC's `site` value
   (`site0` = affinity off vs `siteN` = biased) and the resulting peer-load and
   latency profile.
5. **Bundle-replication scaling.** Re-check `maxBundleSize` /
   `max_content_length`, replication mode (classic / cascading / mounted) and peer
   disk for the **new total** search-head count before, not after, attaching.
6. **Search capacity / WLM.** More SHCs share the same peers; validate search
   concurrency limits and Workload Management against the new load.
7. **Version compatibility.** Confirm SHC member versions are ≥ peer versions and
   that all three SHCs are mutually compatible with the CM.
8. **Per-SHC deployer isolation.** Each SHC has its **own** deployer; do not push
   one SHC's bundle to another's members.
9. **Auth, TLS, time sync.** Confirm management-port reachability, CA trust (if
   mTLS), and NTP across all new members and the CM.
10. **Change governance.** CAB approval, comms and consumer coordination belong to
    the change-management process, not this technical plan.

## 7. References

- Splunk Docs — Integrate the search head cluster with an indexer cluster:
  <https://docs.splunk.com/Documentation/Splunk/9.4.1/DistSearch/SHCandindexercluster>
- Splunk Docs — Search across multiple indexer clusters (the multi-cluster variant):
  <https://docs.splunk.com/Documentation/Splunk/9.4.2/Indexer/Configuremulti-clustersearch>
- Splunk Docs — How search works in an indexer cluster:
  <https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Howclusteredsearchworks>
- Splunk Docs — Create distributed search groups:
  <https://docs.splunk.com/Documentation/Splunk/latest/DistSearch/Distributedsearchgroups>
- Splunk Docs — Multisite indexer cluster architecture:
  <https://docs.splunk.com/Documentation/Splunk/9.4.1/Indexer/Multisitearchitecture>
- See also: the [SHC knowledge-bundle handbook](../handbooks/splunk-shc-knowledge-bundle/00-foundations.md)
  for the three-bundles lexicon (knowledge bundle vs configuration bundles), and
  [ITIL change governance](../methodologies/itil-gouvernance-changement.md) for
  the surrounding change-management process.
