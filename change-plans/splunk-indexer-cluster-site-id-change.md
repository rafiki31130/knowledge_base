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

Rename `<old_site>` → `<new_site>` (repeat the mapping for each site being
renamed). The commands below are the **actual operations** validated in lab,
with generic placeholders. `$CONF` = `$SPLUNK_HOME/etc/system/local/server.conf`
on the node being edited.

> **Do NOT enable maintenance mode for this rename** (proven counter-productive
> in lab — §8, Run 7). `splunk offline` works by having the **manager reassign the
> peer's primary copies to the surviving peers before the peer stops** — but
> maintenance mode **suspends exactly that reassignment**. With maintenance mode
> on, the renamed peer's data drops out of search during the change (multi-second
> gaps; `splunk offline` may even hit its decommission force-timeout), whereas
> **without** maintenance mode continuity is preserved and the manager
> re-replicates normally. Maintenance mode buys nothing here and breaks the one
> guarantee the method relies on.

> **Secret & auth handling (do this on every step).** The cluster `pass4SymmKey`
> lives in `[clustering]` of `server.conf`. **Never rewrite the whole stanza**
> (that would force you to re-inject the secret) — edit **only** the one line you
> need with a targeted `sed`, leaving `pass4SymmKey` untouched. **Never** pass
> credentials in `argv` (`-auth user:pass`): authenticate the CLI via environment
> variables supplied on stdin, e.g.
> `printf 'export SPLUNK_USERNAME=admin\nexport SPLUNK_PASSWORD=%s\n<cmd>\n' "$PW" | bash -s`,
> with `$PW` read once from your secret store.

**1. Manager — declare the new site(s).** Add the new label(s) so old and new
coexist; the manager is not in the data path, so its restart does not interrupt
search.
```bash
sed -i 's/^available_sites = .*/available_sites = <old_site>,<new_site>/' "$CONF"
systemctl restart Splunkd            # or: splunk restart, per your service setup
splunk btool server list clustering | grep -E 'available_sites'   # verify
```

**2. Each peer carrying `<old_site>` — sequentially, never in parallel.** Graceful
offline → relabel → start; confirm the peer is back `Up`/`Searchable` before the
next one.
```bash
# graceful decommission: manager reassigns THIS peer's primaries to the surviving
# peer BEFORE splunkd stops → search stays complete. Plain offline, NOT --enforce-counts.
printf 'export SPLUNK_USERNAME=admin\nexport SPLUNK_PASSWORD=%s\nsplunk offline\n' "$PW" | bash -s
# once splunkd has stopped, relabel only the [general] site line, then start:
sed -i 's/^site = .*/site = <new_site>/' "$CONF"
systemctl start Splunkd
# verify before moving on:  cluster-status shows this peer Up, Searchable, site=<new_site>
```

**3. Manager — map + trim, in the SAME restart.** Drop the old label(s) from
`available_sites` **and** add the `site_mappings`, in one edit/restart (the order
is forced — see box below). If the manager itself sat on a renamed site, relabel
its `[general] site` too.
```bash
sed -i 's/^available_sites = .*/available_sites = <new_site>/' "$CONF"
sed -i '/^\[clustering\]/a site_mappings = <old_site>:<new_site>' "$CONF"  # comma-separate multiple maps
sed -i 's/^site = .*/site = <new_site>/' "$CONF"        # only if the manager was on a renamed site
systemctl restart Splunkd
# RF/SF re-converge as the origin copies re-home to the new site
# (observed: seconds to ~1 minute on a small cluster).
```

**4. Verify convergence.** Poll until met:
```bash
splunk show cluster-status --verbose
# expect: Site replication factor met YES, Site search factor met YES,
#         all peers Up with their NEW site, searchable copies N/N per site, No fixup.
```

> **Why the step-3 order is the *only* valid one.** Three Splunk constraints,
> each verified empirically (§8), box you into the sequence above:
> 1. **`site_mappings` cannot reference a site still in `available_sites`.**
>    Setting `site_mappings = <old_site>:<new_site>` while `<old_site>` is still
>    listed is rejected and crash-loops the manager:
>    `Available site cannot be present in From-relation of tuple in site_mappings`.
>    → `site_mappings` can only appear once the old label is being removed.
> 2. **A peer only registers if its `[general] site` is in `available_sites`.**
>    A peer still on `<old_site>` whose label has been dropped from
>    `available_sites` is **rejected at heartbeat** (`site <old_site> not in
>    available_sites`) and ejected — losing its data from search. → the old
>    label must stay in `available_sites` until **after** the peers are renamed.
> 3. **`site_mappings` re-homes *buckets*, it does not register *peers*.** The
>    `site ∈ available_sites` check runs **before** any `site_mappings`
>    processing, so you cannot shortcut by listing only the target sites up
>    front and letting the mapping pull the old-labelled peers in — it won't.
>
> Combined: rename the peers **while both old and new labels are in
> `available_sites`** (constraint 2), then drop the old labels **and** add their
> `site_mappings` **in the same manager restart** (constraint 1), which re-homes
> the stranded buckets (constraint 3). That is exactly steps 1→3 above.

**Manager and search-head site labels.** The manager must sit on a **real** site
that is in `available_sites` (relabel its `[general] site` in step 3 if it was on a
renamed one). A search head set to `site0` (search-affinity disabled) needs **no**
change — `site0` is reserved for search heads and never appears in `available_sites`.

### 2.3 Cleanup

Once `cluster-status` shows RF/SF met and stable, the `site_mappings` stanza is
**inert but should be removed** at the next maintenance window to avoid future
confusion (§6 reservation 5). Verify RF/SF stay met after removing it and
restarting the manager.

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
- **Manager / peer misalignment.** `available_sites` must list every label a peer
  declares, at every instant. Removing `<old_site>` while a peer still carries it
  gets that peer rejected — always relabel peers (step 2) *before* trimming
  `available_sites` (step 3).
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

**Steps** (symmetric to §2): re-add `<old_site>` to `available_sites`, revert
each peer's `[general] site` (graceful `splunk offline` → edit → `start`), and
remove the `<old_site>:<new_site>` entry from `site_mappings`; or restore the
`server.conf` files from the §2.1 snapshot and restart the affected `splunkd`
instances. Let the cluster re-converge and compare `cluster-status` + bucket
counts against the pre-change snapshot.

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
   because one-peer-per-site makes the wipe approach impractical.
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

**Test bed.** A minimal multisite cluster: 1 cluster manager + 2 indexer peers
(**one peer per site**) + 1 search head, Splunk 9.x, `site_replication_factor =
site_search_factor = origin:1,total:2`, search head on `site0`. Goal: rename the
two indexer sites (`<old1>,<old2>` → `<new1>,<new2>`) with **zero search
interruption** and RF/SF re-met at the end.

**Continuity probe.** A script polled the search head every 2 s for the whole
window, grouping `index=_internal` **by data-source `host`** (the two peers as
event producers) rather than by `splunk_server` (the indexer that answers). This
is the key measurement choice: while a peer restarts, the number of answering
`splunk_server` legitimately drops to 1 — that is **not** an outage. An outage is
a **`host` disappearing** from results, i.e. that peer's data no longer served by
a cross-site copy. The probe logged per-tick availability; a run "passes" only
with **zero** ticks losing a `host`.

**Runs.**

| # | Method tried | Search continuity | RF/SF after | Acceptable? |
|---|---|---|---|---|
| 1 | plain `systemctl restart`, maintenance mode on, **hot** buckets | FAIL — multi-second outages during each peer restart | not met | no |
| 2A | prolonged peer stop, maintenance mode on, **warm** buckets | FAIL — ~6 s gap at primary reassignment | not met | no |
| 2B | **`splunk offline`**, maintenance mode off, warm | **PASS — 0 outage** | not met | no |
| 3 | `splunk offline` + "wait for RF/SF met after each step" gate | FAIL — outage on one peer; **gate timed out** | not met (structural) | no |
| 4 | **`splunk offline` + `site_mappings`** | **PASS — 0 outage** | **MET** | **yes** |

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
- A 5th run tried a "cleaner" ordering — set `site_mappings` **up front**, with
  the old sites still in `available_sites` — and it is **structurally rejected**:
  the manager refuses the config (`Available site cannot be present in
  From-relation of tuple in site_mappings`) and crash-loops.
- A 6th run removed the old sites up front instead — `available_sites = <targets
  only>` **plus** `site_mappings` — testing whether the mapping alone could pull
  the still-old-labelled peers in **without renaming them**. The config is
  **accepted** (the constraint above is lifted), but the **peers are rejected at
  heartbeat** (`site <old_site> not in available_sites`) and ejected — the probe
  recorded a real outage. This proves `site_mappings` is a **bucket** mechanism,
  not a peer-registration one, and that the old label must remain in
  `available_sites` until the peers are renamed.
- Together, runs 4/5/6 show the ordering of §2.2 is the **unique** valid sequence,
  forced by the three constraints listed in the §2.2 box.
- A 7th run repeated the validated method (run 4) but **with maintenance mode
  enabled** throughout — the "standard" reconfiguration practice. It **fails**: the
  renamed peer's data drops out of search during the change (~36 s window in one
  clean run; in another the peer's `splunk offline` hit its ~5-minute decommission
  force-timeout). Cause: `splunk offline` relies on the manager **reassigning the
  peer's primaries before it stops**, and maintenance mode **suspends precisely that
  reassignment**. RF/SF do reconverge once maintenance mode is disabled, but the
  search gap during the change makes it strictly worse than run 4 (0 outage, no
  maintenance mode). → **do not use maintenance mode for this rename** (§2.2).
- An 8th run replaced `splunk offline` with a plain `splunk stop` (hard stop) —
  toggling maintenance mode off between the two peers to let the manager settle.
  It **fails too** (~54 s of outage, ~24–30 s per peer): a hard stop drops the
  peer **without** the manager reassigning its primaries first, so its data is
  unsearchable for the whole restart. The maintenance-mode toggle changed nothing.
  This is the converse confirmation of run 4: **the graceful `splunk offline` —
  which reassigns primaries before the peer stops — is the single feature that
  makes the rename zero-outage. `splunk stop`/`systemctl stop` must not be used.**
- A 9th run tested whether **two peers per site** rescues the hard-stop approach:
  same `splunk stop` + maintenance-mode method, but on a topology with two peers
  in each site (`origin:2,total:3`), processing one site at a time and stopping
  **both** of that site's peers together while the manager was reconfigured. It
  **still fails** (~22 s of outage, both same-site peers absent from search
  together during each stop/restart window). Intra-site redundancy does **not**
  help here: a hard stop of *both* peers of a site removes that site's only
  searchable copies of any bucket whose other copy had not yet been promoted
  elsewhere, and there is no surviving same-site peer to serve it. RF/SF
  reconverge afterwards, but the objective (zero outage) is missed. This
  reinforces the §6.3 reservation: more peers per site only helps if you move
  them **one at a time with `splunk offline`**, never by hard-stopping a whole
  site at once.

**Independent audit.** Run 4 was re-verified by an independent reviewer who
re-derived the result from the raw probe log (0/406 ticks lost a `host` →
100% availability) and from a live cluster query (`Site replication/search
factor met`, searchable copies `N/N` per site, `site_mappings` and
`available_sites` as expected). Verdict: method validated, no blocking
anomalies; the production reserves of §6 were raised by that audit.
