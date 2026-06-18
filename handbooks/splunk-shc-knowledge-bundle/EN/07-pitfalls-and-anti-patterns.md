# Chapter 7 — Pitfalls and anti-patterns

> This chapter consolidates the recurring pitfalls and architectural anti-patterns observed around the three Splunk bundles. An **anti-pattern** is a decision to avoid; a **pitfall** is an unexpected Splunk behavior to expect. The two families are kept apart: you do not "fix" a pitfall, you learn to live with it; you remove an anti-pattern from the architecture.

## Quick refresher

- Anti-patterns are **decisions** made by an admin or app developer. They are removed.
- Pitfalls are **Splunk behaviors** that are not bugs but subtleties. They are learned.
- The distinction is useful for an incident debrief: "we accumulated an anti-pattern" is a governance topic; "we hit a pitfall" is a training topic.

## 1. Content-side anti-patterns (`etc/shcluster/apps/` and Splunk apps)

### A1 — Apps too large in `etc/shcluster/apps/`

A monolithic app of several hundred MB in `etc/shcluster/apps/` stacks two costs: the deployer → captain push is slow (every apply), and the tree is traversed entirely on each SHC internal conf replication cycle. Above 200 MB cumulated in `etc/shcluster/apps/`, the admin feels the apply slow down. Above 500 MB, they start avoiding applies.

**Symptom.** 5+ minute applies, overlapping conf replication cycles, captain complaining in `splunkd.log`.

**Removal.** Split by functional app; pull out embedded data (see A2 below); remove dead or disabled apps; consolidate `local/savedsearches.conf` files that duplicate content.

### A2 — Plain lookups pushed by the deployer

A `historical_dump.csv` lookup of several hundred MB embedded in `etc/shcluster/apps/<app>/lookups/` is doubly costly: it inflates the SHC bundle (deployer apply) and it inflates the SH → peers knowledge bundle (on every cycle). In a non-trivial SHC + indexer cluster, that is tens of GB of useless replication per day.

**Symptom.** SHC bundle or knowledge bundle exceeding several hundred MB without business justification; knowledge bundle replication cycles taking time.

**Removal.** Three options: (a) Externalize the lookup as a dedicated index and use distributed `lookup` or `tstats`; (b) Externalize as a shared KV Store; (c) Reduce upstream (filter, partition). Option (a) is usually the simplest on existing infra.

### A3 — `.git` or build metadata inside an app

An app packaged from a git clone with no clean cycle embeds `.git/`, `node_modules/`, `__pycache__/`, or build artifacts. The bundle grows for no functional reason.

**Symptom.** `du -sh $SPLUNK_HOME/etc/apps/<app>/.git` returns several MB.

**Removal.** Clean the packaging (clean `.tar.gz` or `.spl`). Add `static/`, `appserver/`, `bin/__pycache__/`, `.git/` to the `replicationBlacklist` as a safeguard.

### A4 — `local/` versioned on the deployer for what should be in `default/`

The admin who modifies a `default/savedsearches.conf` on the deployer side but saves it in `local/` confuses the semantics: `default/` is the baseline carried by the app, `local/` is the local override. Systematically versioning `local/` next to `default/` blurs intentional overrides (made by members at runtime) with central configurations.

**Symptom.** Silent conflicts between `local/` pushed by deployer and `local/` created locally on a member; impossible to trace who wrote what.

**Removal.** Convention: `default/` in `etc/shcluster/apps/<app>/`, and `local/` reserved for explicitly centralized overrides (for example a `local/savedsearches.conf` that overrides a `default/` savedsearch with a site-specific parameter).

## 2. Topology-side anti-patterns

### A5 — Refusing cascading at 30 peers

Above 15-20 peers, Splunk recommends cascading ([Cascadingknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.1/DistSearch/Cascadingknowledgebundlereplication)). Keeping classic mode at 30 peers out of convenience stacks bandwidth and latency cost. The "push to the limit": the admin raises `replicationThreads` and `sendRcvTimeout` to mask, with no real gain.

**Symptom.** Push cycles taking several minutes, bandwidth saturated during cycles, searches waiting.

**Removal.** Switch to cascading. It is a configuration change, not an architecture change (the peers stay the same). Test on a pilot site.

### A6 — No mounted with 60 peers + 2 GB bundle

At 60 peers and several hundred MB of bundle, classic or cascading mode consumes network for nothing: at each cycle, the bundle is physically replicated N times or as a tree. Mounted resolves by writing once to a share.

**Symptom.** Knowledge bundle replication taking a visible share of the datacenter's bandwidth.

**Removal.** Evaluate mounted with a storage team that can commit the NFS in SLA. If not possible, stay in cascading and optimize bundle size (see A1, A2).

### A7 — SH / peer version asymmetry

An SH on 9.4.2 and peers on 9.4.0 usually work thanks to Splunk's backward compatibility. But stanzas specific to 9.4.2 in a recent app can fail at map time on a 9.4.0 peer. The cause is rarely explicit — a peer in error on a particular index with no clear message.

**Symptom.** Searches failing on a subset of peers only, with no clear error.

**Removal.** Align SH and peers to the same 9.x minor version. In a migration, migrate the peers first (they tolerate older 9.x bundles) then the SH.

## 3. CLI / operation-side anti-patterns

### A8 — Re-running `splunk apply shcluster-bundle` in a loop

Facing an apply that "seems to do nothing" (because SHC internal conf replication has not yet propagated), the admin re-runs out of habit. Effect: each retry overrides the previous one in the pipeline, with no acceleration of actual propagation.

**Symptom.** Multiple consecutive `apply` in deployer history; captain's `splunkd.log` showing interrupted conf replication cycles.

**Removal.** Wait for the cycle to finish, check with `splunk list shcluster-bundle-status` on the captain side. If propagation is abnormally slow, investigate (ch. 05 branch B), do not retry.

### A9 — Confusing `apply cluster-bundle` (CM) and `apply shcluster-bundle` (deployer)

Running `splunk apply cluster-bundle` on the SHC deployer, or `splunk apply shcluster-bundle` on the CM, fails with a not-very-readable message ("command not applicable on this role" or similar). A rushed admin who types `apply <tab>` and picks the wrong subcommand loses time on diag.

**Symptom.** Command fails immediately, with no push, no propagation trace.

**Removal.** Document in the runbook which apply is done on which node. Best: shell aliases on the nodes, exposing only the relevant command.

### A10 — Trying `/services/admin/distsearch` or other undocumented `/admin/*` endpoints

The `/services/admin/distsearch` endpoint (and its `/services/admin/*` cousins) exists in 9.4 and returns useful information. Splunk explicitly asks **not** to document them publicly nor to automate against them ([RESTprolog](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTprolog) spells out the scope of defensible REST endpoints). Using them in an investigation or monitoring script creates a non-defensible dependency: Splunk can change or remove them at any time without changelog.

**Symptom.** Script that worked and silently breaks after a minor upgrade.

**Removal.** Use the documented `/services/search/distributed/*` and `/services/shcluster/*` endpoints (see ch. 06 §2). For needs not covered, open a Splunk request for a documented endpoint.

## 4. Unexpected Splunk pitfalls

### P1 — `master` → `manager` terminology partially migrated

Splunk 9.x renamed `cluster master` to `cluster manager` on the CM side and `slave` to `peer` on the indexer cluster side. The migration is partial:

- On the **CLI** side: `splunk apply cluster-bundle` remains the subcommand; no `apply manager-bundle`.
- On the **filesystem paths** side: `etc/manager-apps/` on the CM (9.x), but `etc/slave-apps/` on the peer (backward compatibility).
- On the **`splunkd.log`** side: `CMMaster`, `CMPeer` still present — no `CMManager` everywhere.
- On the **REST** side: `/services/cluster/manager/*` (new form) coexists with `/services/cluster/master/*` (old form, redirects). Both work in 9.4.

**Live with it.** Do not be surprised by the mix. Prefer the new form in the code you write; tolerate the old in logs and historical Splunk docs.

### P2 — `slave` → `peer` terminology partially migrated

Symmetric of P1. `slave` historically refers to an indexer cluster peer. The Splunk 9.4 docs have largely migrated to `peer`. `slave` occurrences remain:

- `etc/slave-apps/` on the peer side (backward-compatible path).
- Some historical error or log messages.

**Live with it.** Same as P1. Treat `slave` ≡ `peer` (indexer) in any post-9.0 Splunk context.

### P3 — Undocumented `/services/admin/*` endpoints

See A10 above. These endpoints exist, return useful content, but Splunk does not commit to them.

**Live with it.** Do not use them in automation. Using them ad-hoc, read-only, in a supervised debug is acceptable; scripting them, no.

### P4 — `allowlist` / `denylist` (9.x) coexisting with `whitelist` / `blacklist` (legacy)

Splunk 9.4 has completed the transition to `allowlist` / `denylist` in the new doc pages and stanzas. The older forms `whitelist` / `blacklist` remain functional in the `.conf` (backward-compatible aliases).

**Live with it.** Use the new form in configurations you write. Tolerate the older one in existing bases — no need to migrate en masse, it is cosmetic.

### P5 — The success of `splunk apply shcluster-bundle` says nothing about propagation to the members

The command returns `Successfully applied cluster bundle to captain` as soon as the captain has received and accepted the bundle. This is before the SHC internal conf replication. An admin who does not verify with `splunk list shcluster-bundle-status` on the captain side believes it is done, while the propagation to the 2-3 other members still takes 5-30 seconds.

**Live with it.** Always follow the apply with a `splunk list shcluster-bundle-status` check on the captain side. Do not consider propagation complete until all members show the same `bundle_id`.

### P6 — Restart predicted by `splunk apply` does not trigger by itself everywhere

`splunk apply shcluster-bundle` flags "restart required" in some cases but does not systematically trigger the rolling restart. The decision depends on options (`-push-default-app-conf` raises the probability). The admin thinks the restart will happen automatically and sees the opposite.

**Live with it.** Read the apply output. If "restart required": trigger it explicitly with `splunk rolling-restart shcluster-members`.

### P7 — `splunk apply cluster-bundle` can switch to force-restart silently

Conversely on the CM side: `splunk apply cluster-bundle` may trigger a rolling restart of the peers without explicit request if a modified stanza requires it. The admin learns this by watching the `count of peers in restart` counter climb.

**Live with it.** Always precede the apply with `splunk validate cluster-bundle --check-restart` to predict the behavior.

### P8 — SHC internal conf replication is continuous, not synchronous

The admin who thinks `splunk apply shcluster-bundle` propagates synchronously to the members is wrong. Propagation is done by the SHC internal conf replication, which is continuous (short cycles), not synchronous. It is subtle because for small bundles at low cadence, the effect is imperceptible.

**Live with it.** The delay is `O(conf_replication_period × n)` iterations. For a 5 s default, expect 5-30 s of post-apply propagation, more if the bundle is large.

### P9 — The hash in `var/run/searchpeers/<…>.bundle` is truncated

The hash visible in the file name is typically truncated (8-16 characters, depending on version). This is not the full content hash; it is a shortened fingerprint for naming. The "same hash = same content" comparison remains valid in practice (collisions are astronomically improbable).

**Live with it.** Do not try to recompute the hash from the content to verify — the hash function and truncation method are not documented. Trust the hash as reported.

### P10 — `splunk help distributed` returns subcommands that vary by version

The `splunk list distributed-peer` / `splunk show distributed-peers` subcommands have varied between 9.x minor versions. The exact form of the subcommand to use can be found with `splunk help distributed`. Do not assume a form seen in 9.4.0 works in 9.4.2.

**Live with it.** Check `splunk help distributed` on the current version before scripting.

## Recap

| # | Category | Designation | Removal / live with |
| --- | --- | --- | --- |
| A1 | Content anti-pattern | Apps too large in `etc/shcluster/apps/` | Split, pull data out, remove dead apps |
| A2 | Content anti-pattern | Massive lookups in bundle | Externalize as index or KV Store |
| A3 | Content anti-pattern | `.git`, build artifacts in an app | Clean packaging, preventive blacklist |
| A4 | Content anti-pattern | `local/` versioned on the deployer | Convention `default/` only unless explicit override |
| A5 | Topology anti-pattern | Refusing cascading at 30 peers | Switch to cascading |
| A6 | Topology anti-pattern | No mounted at 60 peers + 2 GB bundle | Evaluate mounted with storage team |
| A7 | Topology anti-pattern | SH / peer version asymmetry | Align versions, migrate peers first |
| A8 | CLI anti-pattern | Re-running `apply shcluster-bundle` in a loop | Wait, check `list shcluster-bundle-status` |
| A9 | CLI anti-pattern | Confusing `apply cluster-bundle` and `apply shcluster-bundle` | Explicit runbook, shell aliases |
| A10 | CLI anti-pattern | `/services/admin/*` endpoints in scripts | Use documented endpoints |
| P1 | Pitfall | `master` → `manager` terminology partial | Tolerate the mix |
| P2 | Pitfall | `slave` → `peer` terminology partial | Identify `slave` ≡ `peer` (indexer) |
| P3 | Pitfall | Undocumented `/services/admin/*` endpoints | Ad-hoc only, no scripts |
| P4 | Pitfall | `allowlist` / `denylist` vs `whitelist` / `blacklist` | Use new form, tolerate old |
| P5 | Pitfall | `apply shcluster-bundle` success ≠ effective propagation | Check `list shcluster-bundle-status` |
| P6 | Pitfall | "Required" restart not triggered alone | Run `rolling-restart shcluster-members` |
| P7 | Pitfall | `apply cluster-bundle` may restart silently | Precede with `validate cluster-bundle --check-restart` |
| P8 | Pitfall | SHC internal conf replication is continuous, not synchronous | Expect `O(conf_replication_period × n)` delay |
| P9 | Pitfall | Hash in file name truncated | Do not recompute, trust the Splunk report |
| P10 | Pitfall | `splunk` subcommands vary by version | `splunk help distributed` before scripting |

## When to escalate / when to decide

- **Persistent anti-pattern.** If an anti-pattern is not removed despite identification (for example A1 on an unmaintained legacy app), it is a governance topic: decide who owns the app, who pays for its refactor or retirement. Not a technical decision.
- **Pitfall that becomes a bug.** If a pitfall manifests as a crash or data loss, it is no longer a pitfall — it is a bug. Open a Splunk Support case with `splunk diag` of the relevant node.
- **Architecture decision.** Topology anti-patterns (A5, A6, A7) are architect decisions. Do not remove them locally without scoping: a change of replication mode impacts the whole SHC + indexer cluster.

## Sources

- [Splunk DistSearch 9.4 — Cascading knowledge bundle replication](https://docs.splunk.com/Documentation/Splunk/9.4.1/DistSearch/Cascadingknowledgebundlereplication)
- [Splunk DistSearch 9.4 — Mounted knowledge bundle replication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Mountedknowledgebundlereplication)
- [Splunk DistSearch 9.4 — Limit the knowledge bundle size](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Limittheknowledgebundlesize)
- [Splunk Indexer 9.4 — Configuration bundle issues](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Configurationbundleissues)
- [Splunk DistSearch 9.4 — Propagate SHC configuration changes](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/PropagateSHCconfigurationchanges)
- [Splunk REST API 9.4 — Prolog (scope of defensible endpoints)](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTprolog)
- [Splunk Admin 9.4 — distsearch.conf (`replicationAllowlist`, `replicationBlacklist`)](https://docs.splunk.com/Documentation/Splunk/9.4.0/Admin/Distsearchconf)
