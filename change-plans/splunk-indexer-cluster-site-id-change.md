# Splunk multisite cluster — in-place site id rename

Change plan for **renaming the `site` label of indexer peers** in an existing
**multisite** indexer cluster, in place, with **zero search interruption** and
**no persistent replication/search-factor degradation**.

This fiche documents **one method** — the only one that achieved both goals in a
lab — namely **`splunk offline` + `site_mappings`**. The naïve in-place rename
(edit `[general] site` and restart) is **proven to fail**; see §1 and the
experiment results in §8.

> **Scope.** This is about *relabelling* sites the cluster already has (e.g.
> `<old_site>` → `<new_site>` across the manager and the peers carrying it),
> keeping the same topology. Two genuinely different operations are **out of
> scope** and have their own official procedures (see References): *moving a peer
> to a different physical site* (offline + wipe + reprovision) and *migrating a
> single-site cluster to multisite*.

> **Authentication.** CLI examples below use `-auth <admin>:<password>` for
> readability. Use the authentication mechanism in force (REST token, SSO, mTLS)
> and **never leave credentials in logs or shell history** (pipe secrets via
> stdin; do not pass them on the command line).

## 1. Why the obvious approach fails

Each cluster member declares its site via `[general] site = <siteX>` in
`server.conf`. The manager uses these labels with `site_replication_factor` and
`site_search_factor` to place bucket copies and designate searchable (primary)
copies.

The "obvious" rename — add `<new_site>` to `available_sites`, edit
`[general] site = <new_site>` on each peer, restart it, then drop `<old_site>` —
**fails on two independent counts** (both observed empirically, §8):

1. **Search outage during peer restarts.** A plain `splunkd` restart drops the
   peer abruptly; the primary (searchable) copies it held are **not** handed off
   first. Searches for that peer's data are incomplete until the peer returns —
   the surviving cross-site copy is not promoted in time. (Under maintenance mode
   the manager does not reassign primaries at all; even outside maintenance mode
   a plain restart is not graceful.)
2. **Persistent RF/SF violation (stranded buckets).** A bucket's **origin site
   is fixed at creation and is not re-homable** by any direct command. Once
   `<old_site>` leaves `available_sites`, a bucket whose origin is `<old_site>`
   needs an origin copy on a site that no longer has a peer → unsatisfiable. The
   manager then reports **`No fixup tasks in progress`** *while* RF/SF stay
   **not met** — it does not even attempt repair. Waiting does not help; this is
   structural. Inserting a "wait for RF/SF met after each step" gate does not
   rescue it either — the gate simply times out after the first peer.

Net effect of the naïve rename: the cluster is left **searchable but
under-replicated**, with no automatic recovery.

## 2. The method — `splunk offline` + `site_mappings`

Each failure is addressed with the matching official mechanism:

- **Continuity ← `splunk offline` (graceful).** It instructs the manager to
  **reassign the peer's primary/searchable copies to the surviving peers before
  the peer stops**, so searchability is preserved across the down window. Use
  **plain `splunk offline`** — *not* `--enforce-counts`, which tries to fully
  re-establish RF/SF before leaving (impossible with one peer per site) and
  blocks.
- **Re-homing the origin copies ← `site_mappings`.** This is Splunk's official
  **site-decommissioning** mechanism. Mapping `<old_site>:<new_site>` tells the
  manager that the origin bucket copies bound to the (now removed) `<old_site>`
  belong to `<new_site>`; the conformance accounting recomputes and the copies
  re-home onto the new site's peer. This is the signal the manager lacks in the
  naïve sequence.

### 2.1 Preconditions

1. The cluster is **healthy**: `splunk show cluster-status` reports
   `Replication factor met` / `Search factor met` and `No fixup tasks in
   progress`.
2. **All buckets are warm and fully replicated.** Hot, not-yet-replicated
   buckets are the real cause of long outages during a peer restart — let them
   roll and replicate before starting. Confirm per-site searchable copies match
   the configured factor.
3. Snapshot the topology for rollback (persist outside the nodes):
   ```bash
   splunk show cluster-status --verbose -auth <admin>:<password>
   splunk list cluster-config -auth <admin>:<password>
   splunk btool server list clustering --debug
   splunk btool server list general --debug
   ```
4. Pre-arrange monitoring suppression (the rename briefly perturbs RF/SF
   accounting and will fire cluster-health alerts).

### 2.2 Procedure (runbook)

Process the cluster **one site at a time**: take **all** of a site's peers down
together, do the manager reconfiguration for that site **while they are down**,
bring them back up on the new label, wait for stabilization, then move to the
next site. `$CONF` = `$SPLUNK_HOME/etc/system/local/server.conf` on the node being
edited.

> **This is the order validated for multiple peers per site** (§8, Runs 12/14) and
> it works for any peer count. With a **single** peer per site you may instead use
> the simpler sequential variant — keep old and new labels coexisting, rename
> peers one at a time, drop the old label only at the very end (§8, Run 4); see the
> note at the end of this section. Below is the general per-site order.

#### Step overview — repeat steps 1→4 for each site `<old_site>` → `<new_site>`

| # | Node | What changes | `server.conf` stanza / key | Action |
|---|------|--------------|----------------------------|--------|
| 1 | **All peers of `<old_site>`** (together) | relabel to the new site, then **leave stopped** | `[general] site` | `splunk offline` each → edit → stay down |
| 2 | **Manager** (single restart) | drop `<old_site>` + add `<new_site>` in `available_sites`; **append** this site's mapping (+ relabel the manager if it sat on this site) | `[clustering] available_sites`, `[clustering] site_mappings` (+ `[general] site`) | restart manager |
| 3 | **All peers of `<old_site>`** | bring them up — they rejoin as `<new_site>` | — | start splunkd |
| 4 | **Manager** | wait until RF/SF met before the next site | — (read-only) | poll `cluster-status` |
| 5 | **Manager** (after the last site — §2.3) | remove the now-inert mappings | `[clustering] site_mappings` | restart manager |

The exact target config for each step is shown below. **Only ever change the
lines shown** — see the editing/secret note before you start. Continuity holds
while a whole site is down because the **cross-site copies** on the other site(s)
keep serving search (that is what `splunk offline` guarantees, by reassigning
this site's searchable primaries to the survivors before each peer stops);
intra-site redundancy is reduced for the window.

> **Do NOT enable maintenance mode for this rename** (proven counter-productive
> in lab — §8, Runs 7/11/13). `splunk offline` works by having the **manager
> reassign the peer's primary copies to the surviving peers before the peer
> stops** — but maintenance mode **suspends exactly that reassignment**. With it
> on, the renamed peer's data drops out of search during the change (tens of
> seconds, the worse the longer it stays on; `splunk offline` may even hit its
> decommission force-timeout). Maintenance mode buys nothing here and breaks the
> one guarantee the method relies on.

> **Editing config safely + auth.** `server.conf` `[clustering]` also holds the
> cluster `pass4SymmKey`. **Change only the specific lines highlighted in each
> step; never rewrite the `[clustering]` stanza wholesale** (that would force you
> to re-inject the secret). A targeted, single-line edit (`sed -i
> 's/^available_sites = .*/.../'`, or your config-management tool) is the safe way
> to apply the target values shown. For the CLI, **never** pass credentials in
> `argv` (`-auth user:pass`): authenticate via environment variables fed on stdin,
> e.g. `printf 'export SPLUNK_USERNAME=admin\nexport SPLUNK_PASSWORD=%s\nsplunk offline\n' "$PW" | bash -s`,
> with `$PW` read once from your secret store.

**Step 1 — Take all peers of `<old_site>` down, relabel, keep them stopped.** Do
each peer's graceful `offline` (back-to-back is fine), set its site, and do **not**
start it yet — the whole site stays down while you reconfigure the manager in
step 2.

Per peer of `<old_site>`:
1. `splunk offline` — **plain, not `--enforce-counts`.** The manager reassigns this
   peer's searchable primaries to the surviving site(s) **before** splunkd stops.
2. Once splunkd has stopped, set the peer's site. Target — `$CONF` on **that peer**:
   ```ini
   [general]
   site = <new_site>                          ; CHANGED: was `<old_site>`
   ```
3. **Leave it stopped** — do not start until step 3.

**Step 2 — Manager: reconfigure for this site, in ONE restart.** With the site's
peers down, drop its old label and add the new one in `available_sites`, and
**append** this site's mapping. If the manager itself sat on `<old_site>`, relabel
its `[general] site` in the same edit. Target — `$CONF` on the **manager**:
```ini
[general]
site = <new_site>                            ; CHANGED — ONLY if the manager sat on <old_site>

[clustering]
available_sites = <new_site>,<other_sites…>  ; drop <old_site>, add <new_site>; keep every OTHER site at its CURRENT label
site_mappings = <old_site>:<new_site>        ; APPEND this map (comma-join with maps from sites already done)
; pass4SymmKey, mode, *_factor                — unchanged
```
Then restart the manager **once**.

> **Worked example — two sites** `site1`→`site3`, `site2`→`site4`:
> - Processing **site1** (site2 not yet touched): `available_sites = site3,site2` ;
>   `site_mappings = site1:site3`.
> - Processing **site2** (site1 already done): `available_sites = site3,site4` ;
>   `site_mappings = site1:site3,site2:site4`.
>
> `available_sites` always lists every label **currently in use** — already-renamed
> sites under their **new** label, not-yet-renamed sites under their **old** label,
> and the current site under its **new** label (its peers are down and relabeled).

**Step 3 — Start the site's peers.** Bring them up; they rejoin as `<new_site>`,
and the manager re-homes their origin buckets via the mapping.

**Step 4 — Verify before the next site.** Poll `splunk show cluster-status
--verbose` until: `Site replication factor met YES`, `Site search factor met
YES`, all peers `Up` on their correct site, searchable copies `N/N` per site, `No
fixup tasks`. Then go back to step 1 for the next site. Expect a brief per-host
re-homing transient with ≥2 peers/site (§6 reservation 3).

> **Why this order is forced.** Three Splunk constraints, each verified
> empirically (§8), shape it:
> 1. **`site_mappings` cannot reference a site still in `available_sites`.**
>    Adding `site_mappings = <old_site>:<new_site>` while `<old_site>` is still
>    listed is rejected and crash-loops the manager:
>    `Available site cannot be present in From-relation of tuple in site_mappings`.
>    → you drop `<old_site>` **and** add its mapping in the **same** edit (step 2).
> 2. **A peer registers only if its `[general] site` is in `available_sites`.**
>    A peer on a label not in `available_sites` is **rejected at heartbeat**
>    (`site <old_site> not in available_sites`) and ejected. → in the per-site
>    order you satisfy this by taking the site's peers **down** before dropping
>    `<old_site>`: nothing is registered on the old label when it disappears, and
>    the peers only start (step 3) once `<new_site>` is in `available_sites`.
>    *(The single-peer sequential variant satisfies the same constraint the other
>    way — by keeping the old label live until every peer is renamed.)*
> 3. **`site_mappings` re-homes *buckets*, not *peers*.** The `site ∈
>    available_sites` check runs **before** any `site_mappings` processing, so the
>    mapping cannot pull a still-old-labelled peer in — it only re-homes the down
>    peers' origin buckets onto the new site.
>
> Net: per site, drop the old label + add the new one + append the mapping in one
> manager restart, **while that site's peers are down** (constraints 1+2), which
> re-homes their buckets (constraint 3).

**Single-peer-per-site variant (Run 4).** With exactly one peer per site you can
avoid taking a whole site down: (1) manager adds **all** new labels up front
(`available_sites = <all old>,<all new>`, one restart); (2) rename peers **one at
a time** (graceful `offline` → set `[general] site` → start, confirm `Up` before
the next); (3) manager drops **all** old labels and adds **all** `site_mappings`
in one final restart. This keeps every site searchable from its own peer until the
moment it flips, and measured a strict zero-outage at one peer per site (§8). It
does **not** generalise cleanly to multiple peers per site — use the per-site
order above there.

**Manager and search-head site labels.** The manager must sit on a **real** site
that is in `available_sites` (relabel its `[general] site` in step 2, in the same
restart, when you process the site it was on). A search head set to `site0`
(search-affinity disabled) needs **no** change — `site0` is reserved for search
heads and never appears in `available_sites`.

### 2.3 Cleanup (step 5)

Once `cluster-status` shows RF/SF met and stable, the `site_mappings` line is
**inert but should be removed** at the next maintenance window to avoid future
confusion (§6 reservation 5).

Target — `$CONF` on the **manager** (after the last site is done, so
`available_sites` now holds only the new labels):
```ini
[clustering]
available_sites = <new_site_1>,<new_site_2>,…   ; unchanged — all sites already on their new label
; site_mappings = <old1>:<new1>,<old2>:<new2>   ; REMOVED — delete the whole line (all maps)
; pass4SymmKey, mode, *_factor                   — unchanged
```
Then restart the manager and confirm RF/SF stay met (`cluster-status`).

## 3. Risks and service interruption

- **Transient under-replication.** During each peer's `offline → relabel →
  start`, that peer's buckets are momentarily below the replication factor —
  fault tolerance is reduced for the window even though **search stays complete**
  via the surviving copy. Size the window against the per-peer restart time and
  avoid overlapping with other risk.
- **Bucket fixup after re-homing.** Removing the old label + `site_mappings`
  triggers the manager to re-replicate origin copies onto the new site. On a
  small cluster this is seconds; on a large one it is a function of bucket count,
  RF/SF and inter-site bandwidth — size the window accordingly.
- **Manager / peer misalignment.** `available_sites` must list every label a
  **running** peer declares, at every instant. Dropping `<old_site>` while a *live*
  peer still carries it gets that peer rejected — in the per-site order you avoid
  this by relabelling and **stopping** the site's peers (step 1) before the manager
  drops `<old_site>` (step 2), and only starting them once `<new_site>` is listed
  (step 3).
- **Inconsistent `server.conf`.** A typo in `site = …` prevents the peer from
  rejoining. Validate with `btool` before restarting.
- **Search affinity.** With `site_search_affinity = true`, post-change queries
  may hit a different indexer set (cold-cache latency). A search head on `site0`
  (affinity off) is unaffected.
- **Forwarder routing.** Forwarders using site-aware indexer discovery pick up
  the new manager view on their next phone-home; static `[tcpout]` lists are
  unaffected by the relabel.

**Service interruption (with this method):** none for **search** (graceful
offline preserves searchability) and none for **ingest** beyond transient
forwarder backoff while a peer restarts. The cluster shows a **degraded
(under-replicated)** state during the window — a redundancy reduction, not an
outage.

## 4. Rollback

**Decision criteria** — roll back if a relabelled peer fails to rejoin (and the
cause is not a trivial typo), RF/SF make no forward progress over a sustained
window, search shows systematic gaps mapped to the change, or the manager is
unstable after its restart.

**Rollback is the same per-site method with `<old_site>` and `<new_site>`
swapped** — the rename is its own inverse. Per site being reverted (`<new_site>`
→ `<old_site>`):

| # | Node | What changes | `server.conf` stanza / key | Action |
|---|------|--------------|----------------------------|--------|
| R1 | **All peers of `<new_site>`** (together) | relabel back to `<old_site>`, leave stopped | `[general] site` | `splunk offline` each → edit → stay down |
| R2 | **Manager** (single restart) | drop `<new_site>` + add `<old_site>`; **remove** the forward map and **append** the reverse one (+ relabel manager if needed) | `[clustering] available_sites`, `[clustering] site_mappings` (+ `[general] site`) | restart manager |
| R3 | **All peers of `<new_site>`** | bring them up — they rejoin as `<old_site>` | — | start splunkd |
| R4 | **Manager** | verify against the pre-change snapshot | — (read-only) | poll `cluster-status` |

The subtlety is **R2's mapping edit**: re-adding `<old_site>` to `available_sites`
forces you to *remove* the forward `site_mappings = <old_site>:<new_site>` in the
**same** edit (a mapping's source may not be in `available_sites` — same
constraint as step 2, reversed), and to *append* the reverse map so the buckets
re-home back. Target — `$CONF` on the **manager**:
```ini
[clustering]
available_sites = <old_site>,<other_sites…>  ; drop <new_site>, re-add <old_site>
site_mappings = <new_site>:<old_site>        ; REMOVE the forward `<old_site>:<new_site>`; APPEND this reverse map
```
Let the cluster re-converge and compare `cluster-status` + bucket counts against
the pre-change snapshot, then remove the reverse mappings (as in §2.3).

**Shortcut:** restoring the `server.conf` files from the §2.1 snapshot and
restarting the affected `splunkd` instances achieves the same end state.

**Point of no return:** there is none that loses data — no peer is wiped and all
data stays searchable throughout. The relabel is reversible at the cost of
another short re-convergence.

## 5. Validation plan

Check the state **after fixup has settled**:

1. **Continuity (during the change).** Run a probe against the search head for
   the whole window and require **zero** loss of result completeness — see §8 for
   the probe design (group by data-source `host`, not by `splunk_server`).
2. **Cluster health.** `splunk show cluster-status` → `Indexing Ready`, every
   peer `Up` with its **new** `Site`, `No fixup tasks in progress`.
3. **Replication & search factors.** `Site replication factor met` **and** `Site
   search factor met` for all indexes; searchable copies per site match the
   configured factor (`btool` / `cluster-status` trackers, e.g. `N/N` per site).
4. **Config.** `available_sites` lists only the new label(s); `site_mappings`
   present until cleanup, then removed.
5. **Search path.** A sample search known to target the relabelled peers'
   data returns complete results in comparable time to baseline.

**Sign-off** = simultaneously: all peers `Up` with new labels, RF/SF met, no
persistent fixup, and the continuity probe reported zero interruption.

## 6. Production reservations

1. **No official "rename a site" procedure.** This method is a deliberate,
   lab-validated **composition** of two official mechanisms (`splunk offline`,
   `site_mappings`); it is not a single blessed Splunk procedure. Treat the
   reserves below as binding before production use.
2. **Scale and load revalidation.** Validated on a **small** dataset, **one peer
   per site**, **without concurrent search load** (§8). Re-validate on
   production-representative bucket counts, peers-per-site and query load before
   a generalised rollout.
3. **Topology with ≥2 peers per site.** With more than one peer per site the
   official *move-a-peer* procedure (offline + wipe + reprovision) becomes cleanly
   applicable per peer and may be preferable; this composition exists precisely
   because one-peer-per-site makes the wipe approach impractical. **Do not promise a
   strict zero-outage at ≥2 peers per site with this method**: lab measurement on a
   freshly rebuilt cluster (§8 control run) still showed a small, stochastic per-host
   gap (seconds to low tens of seconds) during the post-restart re-homing fixup — the
   shutdown windows stay clean, but the fixup is not instantaneous. The strict-zero
   result was specific to one peer per site.
4. **Replication policy.** Validated with `site_replication_factor
   origin:1,total:2` (and equal search factor). The `origin:` constraint is what
   makes the naïve rename strand buckets; confirm the deployed policy and that
   `site_mappings` re-homing behaves as expected for it.
5. **Remove `site_mappings` after convergence** (§2.3). Inert once RF/SF are met,
   but a lasting source of confusion if left in the manager config.
6. **Site label convention.** Labels are `site<N>` (`site1`–`site63`). `site0` is
   **reserved for search heads** (disables search affinity) and must **never**
   appear in `available_sites`; non-numeric labels (e.g. `site_a`) are rejected;
   the **manager must sit on a real site**, not `site0`.
7. **Splunk version.** Behaviour, terminology (`master`/`manager`) and CLI shape
   changed across versions; the lab used a 9.x release. Match the docs to the
   deployed version.
8. **Search head topology.** Standalone SH vs SH cluster vs SHs using
   `site_search_affinity` each behave differently; preserve SHC captaincy.
9. **Forwarders.** Indexer discovery vs static `[tcpout]` vs `site_failover`
   changes how data sources perceive the change.
10. **Backups / snapshots.** Filesystem snapshots may be unavailable depending on
    the storage backend — confirm the safety net before the window; this method
    needs none to be reversible, but it is good practice.
11. **Change governance.** CAB approval, stakeholder comms and downstream-consumer
    coordination belong to the change-management process, not this technical plan.

## 7. References

- Splunk Docs — Decommission a site (source of the `site_mappings` mechanism):
  <https://docs.splunk.com/Documentation/Splunk/9.4.1/Indexer/Decommissionasite>
- Splunk Docs — Multisite indexer cluster architecture:
  <https://docs.splunk.com/Documentation/Splunk/9.4.1/Indexer/Multisitearchitecture>
- Splunk Docs — Use maintenance mode:
  <https://docs.splunk.com/Documentation/Splunk/latest/Indexer/Usemaintenancemode>
- Splunk Docs — Move a peer to a new site (the out-of-scope *move* operation):
  <https://help.splunk.com/en/splunk-enterprise/administer/manage-indexers-and-indexer-clusters/9.0/manage-a-multisite-indexer-cluster/move-a-peer-to-a-new-site>
- See also: [ITIL change governance](../methodologies/itil-gouvernance-changement.md)
  for the surrounding change-management process.

---

## 8. Experiment results (lab validation)

This method was not assumed — it was derived from a controlled lab experiment.
The record below is what justifies the procedure above.

**Test bed.** A minimal multisite cluster: 1 cluster manager + 1 search head on
`site0`, Splunk 9.x. The campaign ran on **two topologies** to separate the
peers-per-site variable:

- **Series A — one peer per site** (2 indexers, `site_replication_factor =
  site_search_factor = origin:1,total:2`). This is where the method was first
  derived and where it reaches a **strict zero outage** (run 4).
- **Series B — two peers per site** (4 indexers, `origin:2,total:3`), a
  deliberately harder topology that, when both same-site peers go down together,
  removes a site's intra-site redundancy. Used to test whether the method scales
  and to probe the residual fixup gap.

Goal in both: rename the two indexer sites (`<old1>,<old2>` → `<new1>,<new2>`)
with **zero search interruption** and RF/SF re-met at the end.

**Continuity probe.** A script polled the search head every 2 s for the whole
window, grouping `index=_internal` **by data-source `host`** (the two peers as
event producers) rather than by `splunk_server` (the indexer that answers). This
is the key measurement choice: while a peer restarts, the number of answering
`splunk_server` legitimately drops to 1 — that is **not** an outage. An outage is
a **`host` disappearing** from results, i.e. that peer's data no longer served by
a cross-site copy. The probe logged per-tick availability; a run "passes" only
with **zero** ticks losing a `host`.

**Runs.** The continuity probe reports per-tick availability (2 s cadence); an
"outage" is a tick where an expected **`host` disappears** from results. Figures
below are availability % and the count of lost ticks / wall-clock gap.

**Series A — one peer per site** (`origin:1,total:2`):

| # | Method tried | Search continuity | RF/SF after | Acceptable? |
|---|---|---|---|---|
| 1 | plain `systemctl restart`, maintenance mode on, **hot** buckets | FAIL — ~95.4%, 3 multi-second outages (~14 s + ~6 s + ~40 s) | not met | no |
| 2A | prolonged peer stop, maintenance mode on, **warm** buckets | FAIL — ~98.5%, ~6 s gap at primary reassignment | not met | no |
| 2B | **`splunk offline`**, maintenance mode off, warm | **PASS — 100%, 0 outage** | not met | no |
| 3 | `splunk offline` + "wait for RF/SF met after each step" gate | FAIL — ~93.3%, ~40 s; **gate timed out** | not met (structural) | no |
| 4 | **`splunk offline` + `site_mappings`** | **PASS — 100%, 0/406 ticks lost** | **MET** | **yes (strict zero)** |
| 5 | `site_mappings` set up front, old sites still in `available_sites` | N/A — config **rejected**, manager crash-loops | — | no (invalid config) |
| 6 | `available_sites = targets only` + `site_mappings`, peers **not** renamed | FAIL — peers ejected at heartbeat (69 lost ticks) | — | no (peers rejected) |
| 7 | run 4 method **with maintenance mode on** | FAIL — ~36 s (or `offline` hit its ~5 min force-timeout) | met after MM disabled | no |
| 8 | **`splunk stop`** (hard) + maintenance mode toggled per peer | FAIL — ~54 s (~24–30 s/peer) | met (~10 min) | no |

**Series B — two peers per site** (`origin:2,total:3`; both same-site peers taken
down together each time — the adversarial choice):

| #   | Method tried                                                      | Search continuity                                                   | RF/SF after | Acceptable?                              |
| --- | ----------------------------------------------------------------- | ------------------------------------------------------------------- | ----------- | ---------------------------------------- |
| 10  | **`splunk stop`** (hard) + maintenance mode "sandwich" (per-site) | FAIL — 98.79%, 11 ticks / ~22 s                                     | met         | no — `stop` strands same-site copies     |
| 11  | **`splunk offline`** + maintenance mode "sandwich" (per-site)     | FAIL — 96.57%, 13 ticks / ~26 s, **all after MM disable**           | met         | no — MM defers the fixup                 |
| 12  | **`splunk offline`, no maintenance mode** (= run 4 generalised)   | **~PASS — 99.35%, 2 ticks / ~4 s** (re-homing transient)            | met         | near — best of series B                  |
| 13  | `splunk offline` + maintenance mode **continuous** (whole rename) | FAIL — 79.05%, 84 ticks / ~165 s                                    | met         | no — **worst run**, MM held throughout   |
| 14  | run 12 re-run on a **clean rebuild** (control)                    | FAIL strict — 95.40%, 12 ticks / ~26 s (inherent re-homing residue) | met         | no strict zero, but the method of choice |

> An intervening attempt (between runs 8 and 10) produced no usable continuity
> measurement and is omitted. Series B figures are availability over the full
> rename window; "ticks" are 2 s probe samples that lost a `host`.

**What each run established.**

- The long outages of run 1 were caused by **hot (not-yet-replicated) buckets**,
  not by maintenance mode — with warm buckets the surviving copy does serve
  (runs 2A/2B). Hence the "all buckets warm and replicated" precondition (§2.1).
- A **plain restart** does not hand primaries off; **`splunk offline`** does,
  eliminating the search gap (run 2B = 0 outage).
- The replication-factor failure is **structural and independent of the shutdown
  method**: a bucket's **origin site is not re-homable** directly. Run 3 proved
  it — after renaming a single peer, the manager reports `No fixup tasks in
  progress` *while* RF/SF stay not met, and a per-step RF/SF gate simply times
  out.
- **`site_mappings`** (the site-decommission mechanism) supplies the missing
  signal to re-home the origin copies. Run 4 combined it with `splunk offline`
  and achieved **both** zero outage **and** full RF/SF reconvergence (immediate
  for the first peer, ~1 minute for the second), with no wipe and no data loss
  (`All data is searchable` throughout).
- Run 5 tried a "cleaner" ordering — set `site_mappings` **up front**, with
  the old sites still in `available_sites` — and it is **structurally rejected**:
  the manager refuses the config (`Available site cannot be present in
  From-relation of tuple in site_mappings`) and crash-loops.
- Run 6 removed the old sites up front instead — `available_sites = <targets
  only>` **plus** `site_mappings` — testing whether the mapping alone could pull
  the still-old-labelled peers in **without renaming them**. The config is
  **accepted** (the constraint above is lifted), but the **peers are rejected at
  heartbeat** (`site <old_site> not in available_sites`) and ejected — the probe
  recorded a real outage. This proves `site_mappings` is a **bucket** mechanism,
  not a peer-registration one, and that the old label must remain in
  `available_sites` until the peers are renamed.
- Together, runs 4/5/6 show the ordering of §2.2 is the **unique** valid sequence,
  forced by the three constraints listed in the §2.2 box.
- Run 7 repeated the validated method (run 4) but **with maintenance mode
  enabled** throughout — the "standard" reconfiguration practice. It **fails**: the
  renamed peer's data drops out of search during the change (~36 s window in one
  clean run; in another the peer's `splunk offline` hit its ~5-minute decommission
  force-timeout). Cause: `splunk offline` relies on the manager **reassigning the
  peer's primaries before it stops**, and maintenance mode **suspends precisely that
  reassignment**. RF/SF do reconverge once maintenance mode is disabled, but the
  search gap during the change makes it strictly worse than run 4 (0 outage, no
  maintenance mode). → **do not use maintenance mode for this rename** (§2.2).
- Run 8 replaced `splunk offline` with a plain `splunk stop` (hard stop) —
  toggling maintenance mode off between the two peers to let the manager settle.
  It **fails too** (~54 s of outage, ~24–30 s per peer): a hard stop drops the
  peer **without** the manager reassigning its primaries first, so its data is
  unsearchable for the whole restart. The maintenance-mode toggle changed nothing.
  This is the converse confirmation of run 4: **the graceful `splunk offline` —
  which reassigns primaries before the peer stops — is the single feature that
  makes the rename zero-outage. `splunk stop`/`systemctl stop` must not be used.**
- **Run 10** tested whether **two peers per site** rescues the hard-stop approach
  (start of series B): same `splunk stop` + maintenance-mode method, but on a
  topology with two peers in each site (`origin:2,total:3`), processing one site at
  a time and stopping **both** of that site's peers together while the manager was
  reconfigured. It **still fails** (98.79%, ~22 s of outage, both same-site peers absent from search
  together during each stop/restart window). Intra-site redundancy does **not**
  help here: a hard stop of *both* peers of a site removes that site's only
  searchable copies of any bucket whose other copy had not yet been promoted
  elsewhere, and there is no surviving same-site peer to serve it. RF/SF
  reconverge afterwards, but the objective (zero outage) is missed. This
  reinforces the §6.3 reservation: more peers per site only helps if you move
  them **one at a time with `splunk offline`**, never by hard-stopping a whole
  site at once.
- **Runs 11 and 12** isolated the **two variables independently** on the two-peers-
  per-site topology, taking *both* peers of a site down **together** each time (a
  deliberately adversarial choice). **Run 11** — with `splunk offline` **and**
  maintenance mode on: the shutdown windows are now **clean** (offline reassigns the
  primaries to the surviving site before stopping, so even both-peers-down loses
  nothing), but an outage of comparable size reappears **right after maintenance
  mode is disabled** (96.57%, ~26 s, all post-disable) — the fixup that maintenance
  mode had suspended runs late and a host's searchable copy is briefly missing. Same
  root cause as run 7. **Run 12** — dropping maintenance mode entirely (same `splunk
  offline`, no maintenance mode) collapses the outage to a brief transient (99.35%,
  2 probe ticks / ~4 s during the post-restart re-homing fixup, on one phase only).
  **Conclusion across the whole series: the
  shutdown method and maintenance mode are separable, and maintenance mode is the
  dominant cause of outage — `splunk offline` without maintenance mode is the only
  combination that approaches zero, and it scales from one to two peers per site.**
  (These runs were measured on a lab cluster relabelled in place several times. A
  control run later rebuilt the cluster from scratch and re-ran the no-maintenance-
  mode method on a pristine baseline — see the dedicated note two bullets down.)
- **Run 13** made the maintenance-mode cost unmistakable by holding it on for the
  **entire** rename (enable once at the start, both sites relabelled under it, a
  single disable at the very end). With two peers per site this is the **worst**
  result of the whole series by a wide margin (79.05%, ~165 s of outage, vs ~4 s with no
  maintenance mode and ~26 s with it toggled per-site). Two effects compound: (1)
  while both peers of the *second* site are down under maintenance mode, the
  manager will not promote the surviving cross-site replica to a searchable
  primary — so that host's data is unsearchable for the **whole** time maintenance
  mode stays on, not just during the restart; and (2) `splunk offline` on the
  second peer cannot finish its graceful decommission under maintenance mode and
  runs all the way to its force-timeout (`decommission_node_force_timeout`, ~5 min),
  stretching the gap further. The lesson is now quantitative: **the outage caused by
  maintenance mode is roughly proportional to how long it stays enabled** — never <
  per-site toggle < continuous. The only combination that approaches zero is
  `splunk offline` with **no maintenance mode at all** (§2.2), and it holds from one
  to two peers per site.
- **Run 14 — control run on a clean rebuild (correction).** To check whether the small
  residual outage of the no-maintenance-mode two-peers-per-site runs (run 12) was an artefact
  of the in-place relabelling, the cluster was **rebuilt from scratch** (all index
  and cluster state wiped, fresh baseline) and the method re-run. Two findings: (1)
  the **slow** factor reconvergence seen earlier *was* an artefact — the rebuilt
  baseline reconverged in seconds; but (2) the **outage did not go to zero — it was
  actually larger** (95.40%, ~26 s vs ~4 s), confined to the post-restart re-homing fixup
  (the renamed site's second peer briefly loses its searchable primary). So the
  residual is **inherent and stochastic**, not a baseline artefact: with **two
  peers per site this method does not reach a strict zero** — expect a few seconds
  to a couple dozen seconds of per-host gap during re-homing. The strict-zero result
  belongs to the **one-peer-per-site** topology (run 4). The shutdown windows
  themselves stay clean throughout; the gap is a transient fixup, not a hard outage.
  This refines reservation §6.3.
- **Naïve "support/vendor" procedure — quantified worst case (anti-pattern).** A
  separately-sourced rename procedure — *edit `[general] site` on every node and
  restart the service; no `splunk offline`, no maintenance mode, no `site_mappings`;
  swap `available_sites` to the new labels only at the very end* — was tested verbatim
  on the two-peers-per-site bed (rolling `systemctl restart` of each peer, then the
  manager). It is the **worst result on record: ~43% search availability** (a single
  outage window of ~4.5 minutes, collapsing at its trough to **one** searchable host)
  **and** RF/SF left **not met** with `No fixup` (stranded buckets). It compounds all
  three failure modes above at once: (1) a plain restart drops the peer's primaries
  with no hand-off (runs 1/8); (2) renaming a peer to a label **not yet** in
  `available_sites` gets it **ejected at heartbeat** and its data drops out (run 6);
  (3) no `site_mappings` strands the origin copies so RF/SF never reconverges (runs
  1-3). Such guidance also tends to misplace `server.conf` (it lives in
  `$SPLUNK_HOME/etc/system/local/`, not under `etc/auth/`). **Any "just edit the site
  and restart" advice is unsafe — use the §2 method.**

**Independent audit.** Run 4 was re-verified by an independent reviewer who
re-derived the result from the raw probe log (0/406 ticks lost a `host` →
100% availability) and from a live cluster query (`Site replication/search
factor met`, searchable copies `N/N` per site, `site_mappings` and
`available_sites` as expected). Verdict: method validated, no blocking
anomalies; the production reserves of §6 were raised by that audit.
