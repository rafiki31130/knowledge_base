# Chapter 8 — Numeric recommendations, registry, glossary

> This chapter consolidates the numeric values proposed by the
> handbook, the registry of dangerous behaviors that feed the
> pedagogical loop, and the glossary. Every value carries the
> caveat **"adapt to context"** — these are the state of the art
> for an SHC of about a thousand users and must be calibrated on
> the real usage baseline.

## 1. Quota tiers by profile

### Reference table

| Parameter | `quota_base` | `quota_plus` | `quota_max` |
| --- | --- | --- | --- |
| `srchJobsQuota` | 5 | 15 | 30 |
| `srchDiskQuota` (MB) | 500 | 2 000 | 5 000 |
| `srchTimeWin` (s) | 86 400 (1 d) | 604 800 (7 d) | 2 592 000 (30 d) |
| `rtSrchJobsQuota` | 0 (no RT) | 2 | 6 |
| `cumulativeSrchJobsQuota` | 0 (off) | 0 (off) | 0 or 200 (admin) |

### Expected distribution

| Profile | Tier | Expected volume per 1 000 users |
| --- | --- | --- |
| Consultative (read-only) | `quota_base` | ~70 % |
| Power user (schedules) | `quota_plus` | ~20 % |
| Application owner (writes) | `quota_max` | ~5 % |
| Delegated admin | `quota_max` + cumulative | ~1 % |

### Criteria for adapting to context

- **Measure for 2 to 4 weeks** ad-hoc concurrency, scheduled
  concurrency, and average search duration (R.1.04 and R.1.05 of
  chapter 5).
- **If a typical consultative user routinely consumes 6+
  concurrent jobs**, the `base=5` tier is underestimated.
- **If less than 5 % of users need `quota_max`**, that is
  consistent. If more than 15 %, the typical-profile model needs
  to be questioned.
- **For an SHC of more than 5 000 users**, raising each tier
  proportionally is **not** the right answer — better to refine
  the profiles (introduce a `quota_premium` between `plus` and
  `max`, for example).

## 2. WLM pool percentages — Search Head side

### Reference table

`search` category at 80 % of total CPU/RAM, `ingest` at 15 %,
`misc` at 5 %.

| Pool | `cpu_weight` | `mem_weight` | `default_category_pool` |
| --- | --- | --- | --- |
| `admin` | 15 | 15 | 0 |
| `scheduled` | 30 | 30 | 0 |
| `ad_hoc` | 35 | 35 | **1** |
| `bulk` | 10 | 10 | 0 |
| `accel` | 10 | 10 | 0 |
| `ingest_default` | 1 | 1 | **1** |
| `misc_default` | 1 | 1 | **1** |

### Criteria for adaptation

- **If the `scheduled` pool saturates** routinely, raise its
  share — or better, stagger scheduling on the saved-search
  side.
- **If `ad_hoc` is under pressure** (B.3.02), raise its share to
  40-45 % at the expense of `scheduled`.
- **The `admin` pool** must never drop below 10-15 % — that is
  what guarantees an admin can diagnose a saturation.
- **For a cluster with GPUs for acceleration**: raise `accel` to
  15-20 % and isolate the pool well.

## 3. WLM pool percentages — indexer side

### Reference table

| Pool | Category | `cpu_weight` / `mem_weight` |
| --- | --- | --- |
| `ingest_default` | ingest | 70 / 70 |
| `ingest_priority` | ingest | 20 / 20 |
| `ingest_bulk` | ingest | 10 / 10 |
| `search_peer_default` | search_peer | 100 / 100 |
| `misc_default` | misc | 100 / 100 |

### Criteria for adaptation

- **If sensitive sourcetypes** represent more than 20 % of the
  ingestion volume, raise `ingest_priority` to 30 %.
- **`ingest_bulk` stays constrained** on purpose — that is what
  protects sensitive ingestion when a bulk dump arrives.

## 4. Monitor-only durations

### Recommendations by axis

| Axis | Monitor-only duration | Justification |
| --- | --- | --- |
| RBAC — composite cutover | 1 to 2 weeks | Capture a weekly cycle of saved searches |
| WLM Search Head — `alert` | 2 to 4 weeks | Capture a monthly cycle (close, reporting) |
| WLM Indexer — `alert` | 2 to 4 weeks | Capture ingestion variability (business cycles) |
| Awareness — pilot wave | 4 weeks | Measure repeat rate (K1) |

### Extension criteria

- **Extend to 4 weeks** if the SHC goes through a sensitive
  monthly cycle (financial close, end-of-month reporting).
- **Extend to 6 weeks** if a migration or freeze is scheduled
  inside the window.

## 5. SAML lifecycle thresholds

### Reference table

| Threshold | Value | Justification |
| --- | --- | --- |
| Inactivity before deactivation | 90 days | NIST SP 800-63B, Microsoft Entra, Okta |
| Quarantine before hard delete | 90 additional days | Allows reactivation, KO handling |
| Total before deletion | 180 days | Standard IAM cycle |

### Criteria for adaptation

- **For a geographically very distributed organization**,
  consider 120 days of inactivity (to absorb seasonal workers).
- **For an organization with very high turnover**, 60 days can
  be enough — but a fast reactivation workflow is required.

## 6. Registry of dangerous behaviors

The consolidated registry classifies platform-observable behaviors
by criticality. It feeds:

- the detection pillar of pedagogical awareness;
- ongoing audit saved searches;
- WLM rule thresholds.

### Criticality scale

| Level | Criterion | Action delay |
| --- | --- | --- |
| Critical (red) | Can break the platform in one operation, exfiltrate a secret, or destroy indexed evidence | Immediate — procedural guardrail required |
| High (orange) | Heavily degrades one axis: progressive saturation, unauthenticated leak, indirect escalation | Short term — hardening quick win |
| Medium (yellow) | Latent trap or modeling ambiguity, induces false assurance in an audit | Medium term — KEDB + integrate into audit SPL |
| Info (white) | Behavior worth knowing to audit correctly, no inherent danger | Watchlist — audit note |

### Registry (excerpt — twenty-three behaviors)

| Id | Behavior | Criticality | Why dangerous |
| --- | --- | --- | --- |
| D-01 | DELETE of a built-in role (`user`/`can_delete`) allowed without confirmation, breaks `admin` by cascade | Critical | Manual restoration required |
| D-02 | POST on an existing role = destructive SET | Critical | Replaces the entire capability list with no warning |
| D-03 | DELETE of an in-use role cascade-deletes its users | Critical | No warning, loss of private resources |
| D-04 | `list_storage_passwords` / `edit_storage_passwords` on a non-IAM role | Critical | Secret exfiltration |
| D-05 | `can_delete` / `delete_by_keyword` outside a nominal admin account | Critical | Deletion of indexed events, loss of evidence |
| D-06 | `admin_all_objects` / `edit_roles` / `change_authentication` outside `admin_iam` | Critical | ACL bypass, pivot to any right |
| D-07 | `srchFilter=*` in a role nullifies all restrictive filters (multi-role OR) | High | A multi-role user sees all data |
| D-08 | `rtsearch` on `power` (or an inherited role) | High | Massive CPU/IO cost at scale |
| D-09 | `schedule_search` / `schedule_rtsearch` on `power` | High | Uncontrolled scheduled-search multiplication |
| D-10 | `accelerate_search` / `accelerate_datamodel` on `user`/`power` | High | Indexer storage + continuous I/O |
| D-11 | `embed_report` on `power` | High | Public embed URLs without authentication |
| D-12 | Missing local quota → multi-role `max()` + default 3 | High | False assurance of a cap |
| D-13 | `cumulativeSrchJobsQuota` on an inert parent without the `enable_cumulative_quota` toggle | Medium | Double trap: placement and toggle |
| D-14 | `srchTimeWin=0` (unlimited) on a parent masks the trace of a bound | Medium | Audit assumes no bound |
| D-15 | Non-revocable inherited capability (`<cap>=disabled` no-op) | Medium | False belief in revocation |
| D-16 | `srchIndexesAllowed=*` does NOT cover the internals `_*` | Medium | Full coverage = `*;_*` |
| D-17 | `-_audit` / `!_audit` syntax invalid (no-op) | High | Exclusion that excludes nothing |
| D-18 | `srchIndexesDisallowed` — precedence and inheritance active | Medium | Reliable structural-exclusion lever |
| D-19 | App/object permissions inherited via `importRoles` | Medium | Object ACL propagated to descendants |
| D-20 | `run_script` / `rest_properties_set` on a non-admin role | High | Arbitrary code / UI bypass |
| D-21 | Role lowercase normalization → invisible collisions | Info | `MyRole` and `myrole` collide silently |
| D-22 | `splunk list role` does not filter; `btool` does not show the merged state | Info | Audit method must rely on REST |
| D-23 | Orphan role / `importRoles` pointing to a nonexistent role | Medium | Inheritance chain broken after DELETE |

### Behavior-to-channel routing

| Criticality | Channel | Action |
| --- | --- | --- |
| Critical | SOC alert + notification to SHC admin | Investigation, incident handling. No pedagogical loop. |
| High | Pedagogical notification (Splunk Web Messages + email digest) | Observation + explanation + alternative. Aggregated on the admin dashboard. |
| Medium | Trend dashboard | Reviewed by admins. User nudge only if it repeats. |
| Info | Periodic audit inventory | No real-time signal. |

## 7. Five measurable KPIs for awareness

| KPI | Definition | Target |
| --- | --- | --- |
| **K1** — Repeat rate | A user who repeats the same behavior more than 30 days later | Decreases over time after notification |
| **K2** — Time to correction | Average delay between notification and observable stop | < 14 days |
| **K3** — Occurrences per behavior | Platform trend per week | Stable or decreasing |
| **K4** — Coverage | % of high-severity behaviors actually routed to a pedagogical channel | > 90 % |
| **K5** — Open rate | % of Splunk Web Messages opened | > 60 % |

## 8. Fifteen consolidated audit SPLs

The fifteen audit searches A-01 through A-12 below cover the
twenty-three dangerous behaviors. All are designed to be
scheduled saved searches, with routing based on the criticality
of the detected behavior.

### A-01 — At-risk capabilities by role

(detailed as R.1.02 in chapter 5).

### A-02 — Roles without a local quota

```spl
| rest /services/authorization/roles splunk_server=local
| where match(title, "^metier_") OR match(title, "^owner_") OR match(title, "^admin_")
| where isnull(srchJobsQuota) OR srchJobsQuota="" OR srchJobsQuota="0"
| table title imported_roles srchJobsQuota imported_srchJobsQuota
```

Targets D-12.

### A-03 — Audit of the `enable_cumulative_quota` toggle

```spl
| rest /services/configs/conf-limits/search splunk_server=local
| table enable_cumulative_quota
| eval verdict = case(
    enable_cumulative_quota="true", "ON",
    enable_cumulative_quota="false", "OFF",
    isnull(enable_cumulative_quota), "DEFAULT (off)",
    true(), "?")
```

Targets D-13.

### A-04 — Roles with `srchFilter=*`

```spl
| rest /services/authorization/roles splunk_server=local
| where srchFilter="*"
| table title srchFilter imported_roles
```

Targets D-07.

### A-04bis — `*` vs. `_*` coverage

```spl
| rest /services/authorization/roles splunk_server=local
| eval has_star = if(mvfind(srchIndexesAllowed, "*")>=0, 1, 0)
| eval has_internal = if(mvfind(srchIndexesAllowed, "_*")>=0
    OR mvfind(srchIndexesAllowed, "_audit")>=0, 1, 0)
| where has_star=1 AND has_internal=0
| table title srchIndexesAllowed
```

Targets D-16.

### A-04ter — Invalid exclusion syntaxes

```spl
| rest /services/authorization/roles splunk_server=local
| eval has_minus = if(mvfind(srchIndexesAllowed, "-*")>=0, 1, 0)
| eval has_bang = if(mvfind(srchIndexesAllowed, "!*")>=0, 1, 0)
| where has_minus=1 OR has_bang=1
| table title srchIndexesAllowed
```

Targets D-17.

### A-04quater — Roles with `srchIndexesDisallowed`

```spl
| rest /services/authorization/roles splunk_server=local
| where isnotnull(srchIndexesDisallowed) AND srchIndexesDisallowed!=""
| table title srchIndexesAllowed srchIndexesDisallowed imported_srchIndexesDisallowed
```

Targets D-18 (useful inventory).

### A-05 — Roles without a `srchTimeWin` bound

```spl
| rest /services/authorization/roles splunk_server=local
| where match(title, "^metier_") OR match(title, "^owner_")
| where srchTimeWin="0" OR srchTimeWin="-1" OR isnull(srchTimeWin)
| table title srchTimeWin imported_srchTimeWin
```

Targets D-14.

### A-06 — `importRoles` inheritance chains

```spl
| rest /services/authorization/roles splunk_server=local
| where mvcount(imported_roles)>0
| eval chain = mvjoin(imported_roles, " -> ")
| table title chain
| sort title
```

Targets D-15, D-23.

### A-07 — Admin-only capabilities elsewhere

```spl
| rest /services/authorization/roles splunk_server=local
| eval all_caps = mvappend(capabilities, imported_capabilities)
| mvexpand all_caps
| search all_caps IN ("admin_all_objects","edit_roles","change_authentication",
    "list_storage_passwords","edit_storage_passwords","can_delete","delete_by_keyword")
  AND NOT title IN ("admin","admin_iam","can_delete")
  AND NOT match(title, "^audit_")
| stats values(all_caps) as caps_admin_only count by title
| sort -count
```

Targets D-04, D-05, D-06.

### A-08 — Multi-role users

```spl
| rest /services/authentication/users splunk_server=local
| where mvcount(roles)>1
| table title realname roles type
```

Targets D-03, D-12 (at-risk combinations).

### A-09 — `power → user` chain intact

```spl
| rest /services/authorization/roles/power splunk_server=local
| eval imports_user = if(mvfind(imported_roles, "user")>=0, "OK", "CASSEE")
| table title imported_roles imports_user
```

Targets D-01 (cascade detection).

### A-10 — Audit of role modifications via `_audit`

```spl
search index=_audit (action=edit_role OR action=create_role OR action=delete_role) earliest=-30d
| table _time user action role old_capabilities new_capabilities
| sort -_time
```

Targets D-01, D-02.

### A-11 — Permissive object ACLs

```spl
| rest /servicesNS/-/-/saved/searches splunk_server=local
| rename "eai:acl.perms.read" as perms_read
        "eai:acl.perms.write" as perms_write
        "eai:acl.sharing" as sharing
        "eai:acl.app" as app
| where sharing="global" OR mvfind(perms_read, "*")>=0
| table app title sharing perms_read perms_write
| sort app title
```

Targets D-19.

### A-12 — Case duplicates in role names

```spl
| rest /services/authorization/roles splunk_server=local
| eval title_lower = lower(title)
| stats values(title) as variantes count by title_lower
| where count > 1
```

Targets D-21.

## 9. Glossary

| Term | Definition |
| --- | --- |
| **Splunk role** | Envelope carrying capabilities, index access, quotas, and inheritance. Declared in `authorize.conf`. |
| **Capability** | Atomic Splunk permission (`search`, `schedule_search`, `rtsearch`, etc.). |
| **`importRoles`** | Purely additive inheritance mechanism between roles. |
| **`srchIndexesAllowed`** | Allow list of indexes. `*` does not cover internals. |
| **`srchIndexesDisallowed`** | Deny list of indexes. Absolute precedence. Inherits via `importRoles`. |
| **`srchFilter`** | SPL fragment automatically applied to a role's searches. Multi-role OR combination. |
| **`srchJobsQuota`** | Per-user cap on concurrent historical jobs. Not inherited. Multi-role `max()`. |
| **`rtSrchJobsQuota`** | Cap on concurrent real-time jobs. |
| **`srchDiskQuota`** | Cap on dispatch-dir space in MB. |
| **`srchTimeWin`** | Maximum time window of a search, in seconds. `-1` = unlimited. |
| **`cumulativeSrchJobsQuota`** | Collective cap (`enable_cumulative_quota` toggle). |
| **Atomic** | Single-responsibility role — `data_*` / `feature_*` / `app_*` / `quota_*`. Never directly assigned to a user (except the floor role). |
| **Composite** | Role assigned to users. No capability of its own. `importRoles` the atomics + redeclares quotas locally. |
| **Typical profile** | Family of composites (`metier_consultative_*`, `metier_operator_*`, `owner_app_*`, `admin_*`). |
| **Tier** | Quota level (`base` / `plus` / `max`) defined by scoping. |
| **Auto-mapping** | Automatic assignment of a Splunk role to the user whose IdP emits a group with a matching name. `enableAutoMappedRoles` toggle. |
| **`roleMap_`** | Explicit IdP-group-to-Splunk-role mapping, maintained by hand. |
| **`defaultRolesIfMissing`** | Safety net when the IdP emits no mapped group. Always `role_no_access`; never `admin`. |
| **Floor role** | Role granted to every authenticated user, via an "all-users" IdP group. Common capabilities + indexes. No local quota. |
| **ACL** | Access Control List of knowledge objects, living in metadata, outside `authorize.conf`. |
| **Knowledge object** | Saved search, dashboard, datamodel, macro, lookup, eventtype. |
| **SAML lifecycle** | Deactivation policy after 90 d of inactivity + hard delete after 90 d of quarantine, with handling of orphan KOs. |
| **WLM pool** | Envelope of CPU / memory resources per cgroup. |
| **WLM category** | `search` / `ingest` / `misc` (+ `search_peer` on the indexer side). |
| **Admission rule** | `[search_filter_rule:*]`. Evaluated before execution. Actions: `filter`, `queue`. |
| **Workload rule** | `[workload_rule:*]`. Placement + monitoring. Actions: implicit placement, `move`, `abort`, `alert`. |
| **`default_category_pool`** | Default pool of a category. Mandatory for each category. |
| **Cgroup** | Linux mechanism for resource isolation. This is what actually applies the pools. |
| **Cluster manager** | Coordinator node of the indexer cluster. Source of truth for peer configuration. Splunk renamed `cluster master` to `cluster manager` starting with 9.0; both terms refer to the same component. |
| **Cluster bundle** | Common peer configuration, propagated by `splunk apply cluster-bundle`. |

## 10. Sources and canonical references

### Splunk

- [Securing Splunk Enterprise 9.4](https://help.splunk.com/en/splunk-enterprise/administer/secure-splunk-enterprise/9.4)
- [Admin Manual 9.4](https://help.splunk.com/en/splunk-enterprise/administer/admin-manual/9.4)
- [authorize.conf spec 9.4](https://help.splunk.com/en/data-management/splunk-enterprise-admin-manual/9.4/configuration-file-reference/9.4.5-configuration-file-reference/authorize.conf)
- [authentication.conf spec 9.4](https://help.splunk.com/en/data-management/splunk-enterprise-admin-manual/9.4/configuration-file-reference/9.4.5-configuration-file-reference/authentication.conf)
- [server.conf spec 9.4](https://help.splunk.com/en/data-management/splunk-enterprise-admin-manual/9.4/configuration-file-reference/9.4.5-configuration-file-reference/server.conf)
- [SAML SSO 9.4](https://help.splunk.com/en/splunk-enterprise/administer/manage-users-and-security/9.4/use-saml-as-an-authentication-scheme-for-single-sign-on)
- [Workload Management 9.4](https://help.splunk.com/en/splunk-enterprise/administer/manage-workloads/9.4)
- [Indexer Clusters 9.4](https://help.splunk.com/en/splunk-enterprise/administer/manage-indexers-and-indexer-clusters/9.4)
- [Splunk Validated Architectures](https://docs.splunk.com/Documentation/Splunk/latest/Architecture/WhatisaSplunkValidatedArchitecture)
- [Splunk Lantern](https://lantern.splunk.com/)
- [Splunk Blog — Best practices for Workload Management](https://www.splunk.com/en_us/blog/platform/best-practices-for-using-splunk-workload-management.html)

### External IAM references

- [NIST SP 800-63B — Digital Identity Guidelines](https://pages.nist.gov/800-63-3/sp800-63b.html)
- NIST SP 800-53 AC-5 (Separation of Duties) and AC-6 (Least Privilege)
- Microsoft Entra ID — lifecycle management documentation
- Okta — lifecycle management documentation
