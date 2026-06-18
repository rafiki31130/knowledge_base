# Splunk SHC Knowledge Bundle Handbook

> 🇫🇷 **Version française disponible** : [`../README.md`](../README.md)

> A short manual for the administrator or architect of an on-prem Splunk Enterprise who can already deploy a Search Head Cluster and an indexer cluster, but who is tripped up by the real behavior of *knowledge bundles* in a distributed environment. Three different Splunk mechanisms all carry the word "bundle": this handbook pulls them apart, describes how each one propagates, provides the decision tree for the most frequent incidents, and consolidates the CLI / REST / logs / SPL investigation toolbox.

## Note on the French-to-English mapping

This handbook was originally written in French. The English version lives in this `EN/` subfolder and mirrors the French version chapter-for-chapter. File names have been adapted to be idiomatic in English rather than transliterated. The mapping is:

| Source (FR) | This version (EN) |
| --- | --- |
| `README.md` | `EN/README.md` |
| `00-foundations.md` | `EN/00-foundations.md` |
| `01-bundle-shc-constitution.md` | `EN/01-shc-configuration-bundle.md` |
| `02-bundle-search-constitution.md` | `EN/02-knowledge-bundle-constitution.md` |
| `03-replication-vers-peers.md` | `EN/03-replication-to-peers.md` |
| `04-sequence-recherche-distribuee.md` | `EN/04-distributed-search-sequence.md` |
| `05-troubleshooting-arbre-de-diag.md` | `EN/05-troubleshooting-decision-tree.md` |
| `06-investigations.md` | `EN/06-investigations.md` |
| `07-pieges-anti-patterns.md` | `EN/07-pitfalls-and-anti-patterns.md` |
| `99-cheatsheet-diag-rapide.md` | `EN/99-diag-cheatsheet.md` |

The French version remains canonical. If the two versions ever diverge, the French version is the source of truth.

## What this handbook is and isn't

**Is.** A plumbing book: the real mechanics of how configurations propagate in a Search Head Cluster (SHC) paired with an indexer cluster. It separates from the start three mechanisms that the Splunk documentation conflates under the word "bundle" — *SHC configuration bundle* (deployer → members), *search knowledge bundle* (search head → search peers), *indexer cluster configuration bundle* (cluster manager → peers) — and gives each one a dedicated chapter. It then consolidates the decision tree for the most frequent incidents and the investigation toolbox (CLI, REST, `splunkd.log` filters, SPL `index=_internal`).

**Isn't.** An SHC deployment tutorial. An installation manual. An introduction to Splunk. A Splunk Cloud guide (where the deployer is hidden and the ops mechanics change). A SmartStore manual — SmartStore changes the bucket mechanics, not the bundle mechanics; it is mentioned as a pointer, never detailed. The deployment server for forwarders is explicitly out of scope; it is covered elsewhere in the KB (`splunk/concepts/deployment-server.md`).

## Persona

You administer or architect a Splunk Enterprise 9.x on-prem. You know how to stand up a Search Head Cluster, you can tell a *captain* from a *member*, you read a `server.conf` without hesitation, you understand what `_internal` is and you know how to open a `splunkd.log` at the right time. You have already spent half a day trying to figure out why `splunk apply shcluster-bundle` does not seem to do anything — or why a search stays stuck "waiting for bundle" on a single peer. You want a defensible reference and an investigation checklist, not a course.

You are **not** the audience if you are starting out on Splunk, if you are an SPL analyst without admin access (see the `splunk-user-handbook` in the same KB), if you work on Splunk Cloud (ops model too different), or if you are looking for the install procedure for an SHC.

## Scope

- **Splunk Enterprise 9.x on-prem**, examples pinned to **9.4**.
- **SHC + indexer cluster** together — this is the archetype where bundle confusion is born. An SHC alone or an indexer cluster alone still reads with this handbook, but the two together motivated writing it.
- Covers the **three mechanisms** called "bundle" in an admin's daily life: SHC configuration bundle, distributed-search knowledge bundle, indexer cluster configuration bundle. The title puts the emphasis on the knowledge bundle (the most subtle), but chapter 00 frames all three.
- Covers the **three knowledge-bundle SH → peer replication topologies**: *classic*, *cascading*, *mounted*.
- Covers the **observable** incidents (stuck search, bundle too large, peer outside the cluster, divergent hash, restart not triggered) and provides the matching decision tree.

### Out of scope

- **Splunk Cloud** — deployer hidden, different ops model.
- **SmartStore** — pointed to in chapter 03, not detailed. Changes the bucket mechanics, not the bundle mechanics.
- **Deployment server for forwarders** — already covered in the KB (`splunk/concepts/deployment-server.md`).
- **SOAR, Observability, Enterprise Security, ITSI**.
- **Splunk before 9.0** and **10.x** — refresh project when 10.x is dominant.

## How to use this handbook

Chapters are designed to be read independently, but the proposed order is pedagogical: chapter 00 lays down the defensible lexicon used everywhere in the book, chapters 01 → 04 describe each mechanism in the order an admin encounters them, chapter 05 provides the decision tree to enter by symptom, chapter 06 is the **toolbox** (CLI, REST, logs, SPL) that you reopen during an incident, chapter 07 consolidates the anti-patterns to ban, chapter 99 is the printable cheatsheet.

Facing an incident, the entry point is always the same: chapter 05 (decision tree) to characterize the symptom, chapter 06 (investigations) for the precise commands, chapter 99 (cheatsheet) if you already roughly know where you are going.

## Table of contents

| # | Chapter | Topic |
| --- | --- | --- |
| 00 | [Foundations — three bundles, one word](./00-foundations.md) | Defensible lexicon, distinct mechanics, owners |
| 01 | [SHC configuration bundle constitution on the deployer](./01-shc-configuration-bundle.md) | `etc/shcluster/apps`, `splunk apply shcluster-bundle`, internal conf replication |
| 02 | [Knowledge bundle constitution on the search head](./02-knowledge-bundle-constitution.md) | Consolidation, hash, delta vs full, `distsearch.conf` |
| 03 | [Replication to search peers](./03-replication-to-peers.md) | Classic, cascading, mounted; `var/run/searchpeers/`; partial failures |
| 04 | [Distributed search sequence](./04-distributed-search-sequence.md) | bundle ready → fan-out → map → reduce |
| 05 | [Troubleshooting — decision tree](./05-troubleshooting-decision-tree.md) | Symptom → hypotheses → action → escalation criterion |
| 06 | [Investigations — toolbox](./06-investigations.md) | CLI, REST, `splunkd.log` filters, SPL `index=_internal` |
| 07 | [Pitfalls and anti-patterns](./07-pitfalls-and-anti-patterns.md) | Content, topology, CLI, 9.x terminology |
| 99 | [Quick diag cheatsheet](./99-diag-cheatsheet.md) | One printable page |

## Conventions

### Anonymization placeholders

Extends the canonical table in the KB `handbooks/README.md` with the names specific to the SHC + indexer cluster ecosystem used throughout the handbook.

| Category | Canonical value |
| --- | --- |
| Generic hostnames (inherited) | `host01`, `web01`, `db01` |
| Search peers (indexers) | `peer01`, `peer02`, `peer03` |
| Search head cluster members | `shcMember01`, `shcMember02`, `shcMember03` |
| Captain (role, can rotate to any member) | `captain01` |
| SHC deployer | `deployer01` |
| Cluster manager (indexer cluster, 9.x terminology) | `cm01` |
| Standalone search head (outside SHC, used as a counter-example) | `sh01` |
| Forwarders | `uf01`, `hf01` |
| Domain | `example.com`, `corp.example.com` |
| IP / CIDR | `10.0.0.0/24`, `192.0.2.0/24` (RFC 5737), `2001:db8::/32` |
| Users | `alice`, `bob`, `svc_app` |
| Internal apps | `my_company_app`, `soc_app` |
| Indexes | `main`, `security`, `os`, `network`, `summary_app01` |
| SHC member GUID (shape) | `00000000-0000-0000-0000-000000000001` through `…003` |
| Paths | `$SPLUNK_HOME/etc/shcluster/apps/`, `$SPLUNK_HOME/var/run/searchpeers/<sh_guid>-<epoch>-<hash>.bundle` |

Any real value (hostname, IP, GUID, hash, timestamp) is forbidden. The handbook is published in a public GitHub repo; see the KB `CONTRIBUTING.md` for the details of rule R7.

### Command notation

- **Splunk CLI**: ` ```bash ` fence, one command per line, prefixed `splunk` (never `./splunk`, never an absolute path). Long options on their own line with `\`.
- **REST API**: ` ```bash ` fence, in the form `curl -k -u admin:<password> https://<host>:8089/services/...`. The `<password>` placeholder never carries a real value. HTTP method spelled out (`-X GET`, `-X POST`), parameters as `-d`. Mgmt port = `8089`, SHC replication port = `8090` (to be verified on `server.conf` `[shclustering] mgmt_uri` of the target member).
- **`splunkd.log` excerpts**: ` ```text ` fence, 1 to 3 lines maximum per example, anonymized (timestamp `YYYY-MM-DD HH:MM:SS.sss`, canonical GUID `00000000-0000-0000-0000-000000000001`, hash placeholder `aaaaaaaa…`).
- **SPL**: ` ```spl ` fence, time range always explicit, one pipe per line when the pipeline exceeds 80 columns.
- **`.conf`**: ` ```ini ` fence with the enclosing `[…]` stanza, never an excerpt without a stanza.

### 9.4 terminology

Splunk 9.4 has completed its terminology transition from `master` → `manager` (cluster manager) and from `slave` → `peer` (search peer). The logs and certain REST endpoints retain the older form. When the handbook cites a legacy term (for example `CMMaster` in `splunkd.log`), it is made explicit. Also worth noting: Splunk 9.4 uses `allowlist` / `denylist` (current form) while keeping `whitelist` / `blacklist` as backward-compatible aliases; the handbook uses the current form and flags the alias on first occurrence (chapter 02).

### Citing sources

Every factual claim points inline to the official Splunk 9.4 documentation (`docs.splunk.com/Documentation/Splunk/9.4.x/...`) or to the Splexicon. The Splexicon is cited for definitions only, never to describe behavior. Lantern and the Splunk blog are accepted as context but never as a standalone reference. Each chapter ends with a `## Sources` section that consolidates its citations.

## Global sources

### Distributed Search Manual 9.4

- [Knowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Knowledgebundlereplication)
- [Whatsearchheadssend](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Whatsearchheadssend)
- [Classicknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.1/DistSearch/Classicknowledgebundlereplication)
- [Cascadingknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.1/DistSearch/Cascadingknowledgebundlereplication)
- [Mountedknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Mountedknowledgebundlereplication)
- [Limittheknowledgebundlesize](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Limittheknowledgebundlesize)
- [Troubleshootknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Troubleshootknowledgebundlereplication)
- [Configuredistributedsearch](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Configuredistributedsearch)
- [SHCarchitecture](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/SHCarchitecture)
- [PropagateSHCconfigurationchanges](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/PropagateSHCconfigurationchanges)
- [SHCdeploymentoverview](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/SHCdeploymentoverview)
- [ViewSHCstatus](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus)
- [HowconfrepoworksinSHC](https://docs.splunk.com/Documentation/Splunk/9.4.1/DistSearch/HowconfrepoworksinSHC)

### Admin / Conf references 9.4

- [Distsearchconf](https://docs.splunk.com/Documentation/Splunk/9.4.0/Admin/Distsearchconf)
- [Serverconf](https://docs.splunk.com/Documentation/Splunk/9.4.2/Admin/Serverconf)

### Indexer Cluster 9.4

- [Updatepeerconfigurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Updatepeerconfigurations)
- [Managecommonconfigurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Managecommonconfigurations)
- [Configurationbundleissues](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Configurationbundleissues)
- [Managesinglepeerconfigurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Managesinglepeerconfigurations)
- [Restartthecluster](https://docs.splunk.com/Documentation/Splunk/9.4.2/Indexer/Restartthecluster)
- [Configuremanagerwithserverconf](https://docs.splunk.com/Documentation/Splunk/9.4.1/Indexer/Configuremanagerwithserverconf)

### REST API Reference 9.4

- [RESTprolog](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTprolog)
- [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster)

### Troubleshooting 9.4

- [WhatSplunklogsaboutitself](https://docs.splunk.com/Documentation/Splunk/9.4.2/Troubleshooting/WhatSplunklogsaboutitself)

### Splexicon (definitions only)

- [Knowledgebundle](https://docs.splunk.com/Splexicon:Knowledgebundle)
- [Configurationbundle](https://docs.splunk.com/Splexicon:Configurationbundle)
- [Searchpeerreplication](https://docs.splunk.com/Splexicon:Searchpeerreplication)
- [Searchpeer](https://docs.splunk.com/Splexicon:Searchpeer)
- [Searchheadcluster](https://docs.splunk.com/Splexicon:Searchheadcluster)
- [Deployer](https://docs.splunk.com/Splexicon:Deployer)
- [Clustercaptain](https://docs.splunk.com/Splexicon:Clustercaptain)
- [Managernode](https://docs.splunk.com/Splexicon:Managernode)

## Versioning note

The handbook is written against **Splunk Enterprise 9.x on-prem**, examples pinned to **9.4**. Splunk Cloud, SmartStore, Splunk before 9.0 and Splunk 10.x are explicitly out of scope.

Three versioning details to know before reading:

1. **`allowlist` / `denylist` terminology**: 9.4 uses both forms. The handbook uses the current form (`allowlist`, `denylist`) and flags the backward-compatible aliases `whitelist` / `blacklist` on their first occurrence (chapter 02).
2. **`/services/admin/distsearch` endpoint**: an admin endpoint not publicly documented by Splunk. A temptation to avoid — it exists in 9.4 but is not meant to be called outside of support. The handbook does not list it as a tool; it is treated in chapter 07 as a pitfall ("non-defensible admin endpoint").
3. **`splunkd.log` components**: among the components relevant to the bundle, Splunk only documents `DistributedBundleReplicationManager` individually. The others (`BundleReplicator`, `ConfReplication*`, `CMMaster`, `CMPeer`, `ApplyBundleHandler`) are **observed empirically** in `splunkd.log` 9.4 with no dedicated reference page. Chapter 06 makes this explicit through a "Source / status" column.

When a 9.x minor diverges on a behavior (for example a change in the bundle path between 9.4.0 and 9.4.2), the relevant chapter flags it inline.
