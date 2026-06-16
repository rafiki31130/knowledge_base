# Chapter 4 — Splunk 9.4.6 empirical findings

> This chapter consolidates the behaviors observed on Splunk
> Enterprise 9.4.6 that **diverge** from the official documentation
> or significantly refine it. Each finding is documented as:
> documented hypothesis, test run, observed result, consequence for
> governance. This is the material to cite when defending a
> technical decision against a poorly informed counter-proposal.
>
> Every finding below was observed empirically on a Splunk
> Enterprise **9.4.6** single-instance lab on Linux (cgroups v2
> kernel). When the divergence is against the official Splunk 9.4
> documentation, the documentation source is cited.

## How to read a finding

Every finding follows the same structure:

- **Documented hypothesis**: the expected behavior per the official
  documentation (with link).
- **Test run**: the procedure used to reproduce the observation
  (REST, SPL, CLI).
- **Observed result**: what the 9.4.6 binary actually does.
- **Consequence for governance**: why this finding changes the way
  the model is designed.

## RBAC family

### F-RBAC-01 — Non-revocability of an inherited capability

**Documented hypothesis.** The Splunk
[Roles and capabilities 9.4](https://help.splunk.com/en/splunk-enterprise/administer/secure-splunk-enterprise/9.4/define-roles-on-the-splunk-platform/about-defining-roles-with-capabilities)
documentation describes `importRoles` as an inheritance mechanism.
It would be reasonable to expect that an imported capability can be
revoked at the child role with an explicit declaration — that is
how Allow/Deny systems from other vendors work (AWS IAM in
particular).

**Test run.** Two roles, `r_parent` and `r_child`.

```ini
[role_r_parent]
capabilities = search;schedule_search;rtsearch
srchIndexesAllowed = main

[role_r_child]
importRoles = r_parent
capabilities = search;schedule_search
# Attempt 1: explicit declaration
rtsearch = disabled
```

Create a user carrying `r_child` and check their ability to launch
a real-time search via REST:

```bash
curl -sk -u <user>:<pw> \
  https://<sh>:8089/services/search/jobs \
  -d 'search=index=main' \
  -d 'search_mode=realtime' \
  -d 'earliest_time=rt' -d 'latest_time=rt'
```

**Observed result.** The real-time job is accepted. `rtsearch`
remains **effective** at runtime. The `rtsearch = disabled`
declaration is stored literally in
`etc/system/local/authorize.conf` with no warning in `splunkd.log`.
The test was repeated with other shapes (pure omission, `rtsearch =`,
`rtsearch = 0`, `rtsearch = false`) — all equivalent to the nominal
inherited behavior.

Inheritance is therefore **purely additive**: there is no
subtraction mechanism at the child level.

**Consequence for governance.** Revocation happens **at the atomic
parent level**, never by subtraction in a composite. If a composite
must not be able to schedule real-time searches, you **don't
import** the `feature_rt` atomic. You do not try to disable it
after import.

This constrains the design of the hybrid model: every sensitive
capability must be **isolated in its own atomic role** so it can be
included or excluded, never removed after inclusion.

### F-RBAC-02 — Non-inherited quotas, multi-role `max()`

**Documented hypothesis.** The REST output of
`/services/authorization/roles` exposes `imported_*` fields for
quotas: `imported_srchJobsQuota`, `imported_srchDiskQuota`,
`imported_rtSrchJobsQuota`. A reasonable reader would expect these
inherited quotas to apply to a user of the child role.

**Test run.** An atomic `quota_low` carrying `srchJobsQuota=1`, and
a role `r_user` that imports it without redeclaring its own quota:

```ini
[role_quota_low]
srchJobsQuota = 1

[role_r_user]
importRoles = quota_low
capabilities = search
srchIndexesAllowed = main
```

Create a user `u_test` carrying `r_user` and launch three
concurrent historical searches via REST.

**Observed result.** **All three searches are admitted.** The REST
output for `r_user` does show `imported_srchJobsQuota=1`, but the
9.4.6 binary **does not enforce** that cap. The effective value is
the system default `srchJobsQuota=3` from the `[default]` stanza of
`authorize.conf`, because `r_user` does not redeclare its own value.

**Additional test — the multi-role `max()` rule.** Two roles
assigned directly to a user, one with `rtSrchJobsQuota=2`, the
other with `rtSrchJobsQuota=6`. Launch four concurrent real-time
searches:

- observed result: 4 RUNNING / 0 QUEUED — the effective cap is
  `max(2, 6) = 6`, never the minimum.

A test with `cumulativeRTSrchJobsQuota` confirms the same rule,
and that cumulative cap is only enforced when the toggle
`limits.conf [search] enable_cumulative_quota = true` is enabled.

**Consequence for governance.** Any design of the quota model
must lay down two rules:

1. Quotas **are redeclared locally** in every final role assigned
   to a user. No composite role should "passively" inherit its
   quotas. Atomic roles `data_*`, `feature_*`, `app_*` **never**
   carry a quota.
2. The cap guarantee is built through **SAML assignment
   discipline** (a user carries only one composite at a time,
   except for validated cases). Without that discipline, the
   `max()` effect opens the door to uncontrolled accumulation.

This is the **by-construction fragility** of the quota layer, and
it is precisely what WLM (axis 4, chapters 6-7) compensates: WLM
caps the resource consumed, not the number of jobs admitted.

### F-RBAC-03 — `*` does not cover internal indexes

**Documented hypothesis.** For a reader familiar with Unix
wildcards or regular expressions, `srchIndexesAllowed=*` suggests
"all indexes."

**Test run.** Deploy two roles with respectively
`srchIndexesAllowed=*` and `srchIndexesAllowed=*;_*`, assigned to
distinct users. Each user runs `| stats count by index` over the
maximum possible duration.

**Observed result.** The `*` user sees zero events on `_audit`,
`_internal`, `_telemetry` and other `_*`. The `*;_*` user sees
everything. The `*` wildcard **does not include** internal indexes
on 9.4.6.

**Additional test.** Naming `_audit` explicitly in
`srchIndexesAllowed = _audit` opens only `_audit`, not the other
internals. You need either `*;_*` (full coverage) or an
enumeration of the required internals.

**Consequence for governance.** Any "audit" role
(`role_audit_inspector`, `data_audit`) must explicitly declare
`_audit` (and as needed `_internal`, `_telemetry`) in its
`srchIndexesAllowed`. No business role carries `*` — it declares
its nominal indexes. The `*` wildcard is reserved for technical
administration roles.

### F-RBAC-04 — `srchIndexesDisallowed` takes precedence and inherits

**Hypothesis.** The 9.4 documentation states that
`srchIndexesDisallowed` takes precedence over `srchIndexesAllowed`
within a role. Multi-role behavior and inheritance via
`importRoles` were not documented unambiguously.

**Test run.** Three sub-tests: intra-role precedence (the same
role carries `srchIndexesAllowed=idx_a;idx_b` and
`srchIndexesDisallowed=idx_b`), inheritance (a child role imports
a parent carrying `Disallowed`), multi-role combination (a user
carries two roles, one allowing `idx_b`, the other disallowing
it).

**Observed result.**

- Intra-role precedence: `idx_b` is **invisible** as expected.
- Inheritance: `srchIndexesDisallowed` **propagates** via
  `importRoles` and stays **effective** in the child. The REST
  field `imported_srchIndexesDisallowed` exists (which refutes a
  community hypothesis that assumed it absent).
- Multi-role: the rule is **most-restrictive** — the disallowing
  role wins over the allowing role (the inverse logic of the
  `max()` rule on quotas).

**Consequence for governance.** `srchIndexesDisallowed` is a
**reliable** structural-exclusion lever that can be placed on a
`data_*` atomic and that propagates cleanly to composites. It is
in particular the tool for excluding `_audit` from non-audit
business roles, even when `srchIndexesAllowed` would include `*;_*`
for historical reasons.

### F-RBAC-05 — `-_audit` syntax is invalid

**Hypothesis.** Several community documents suggest that
`srchIndexesAllowed=*;-_audit` excludes `_audit` from the wildcard.

**Test run.** A role with `srchIndexesAllowed=*;-_audit`. Run
`| stats count by index` on `_audit`.

**Observed result.** The user **can read** `_audit` (count > 0).
The string `-_audit` is stored literally, treated as a
(nonexistent) index name, and **excludes nothing**. The same
result with `!_audit`.

**Consequence for governance.** Exclusion **must** go through
`srchIndexesDisallowed`. Any internal documentation mentioning
`-<index>` or `!<index>` syntax is wrong and must be corrected.

### F-RBAC-06 — `srchFilter` combines with OR

**Hypothesis.** An intuitive reader might expect `srchFilter` to
combine with AND across a user's roles (each restrictive filter
stacks).

**Test run.** A user carries one role with `srchFilter="region=eu"`
and another with `srchFilter="*"` (or an empty field). They run
`| stats count by region`.

**Observed result.** The user sees **all** regions. The
multi-role combination is **OR**: `region=eu OR *` = everything.

**Consequence for governance.** **Ban `srchFilter=*`** on every
business role. Leave the field empty instead — semantically
equivalent on the permissions side but avoids accidentally
nullifying the restrictive filters of other roles.

### F-RBAC-07 — App ACL: write without read = invisible

**Documented hypothesis.** The Splunk documentation on knowledge
object permission management describes the ACL `perms.read=role_A`
and `perms.write=role_B` as granting read to `role_A` **and**
write to `role_B` (the "read OR write" model).

**Test run.** Create a saved search in an app with
`perms.read=role_consultative` and `perms.write=role_owner`
(without including `role_owner` in `perms.read`). A user carrying
only `role_owner` opens the app.

**Observed result.** The saved search is **invisible (404)** to
the `role_owner` user — it doesn't appear in the saved-search list
of the app, and the direct URL returns 404.

**Consequence for governance.** **Always pair read + read/write**
in ACLs: `perms.read=role_A;role_B`, `perms.write=role_B`. Atomic
roles `app_<prod>` must come in pairs `app_<prod>_read` and
`app_<prod>_rw`; a composite that needs to write imports both.

### F-RBAC-08 — Major operational REST traps

**Three traps** observed empirically on the 9.4.6 REST API that
can **silently break** the platform.

**Trap 1 — POST on an existing role = destructive SET.** A
partial POST to `/services/authorization/roles/<role>` that
mentions only `capabilities=cap1` **replaces the entire** list of
capabilities of the role. No warning. The mandatory pattern is
**GET → local merge → full POST** with the complete list of
fields.

**Trap 2 — DELETE on a built-in allowed without confirmation.**
`DELETE /services/authorization/roles/user` returns HTTP 200. The
cascade consequence: `power.importRoles` is reset to `[]`, `admin`
loses inheritance of `search`, the entire platform refuses jobs.
Manual restoration from a snapshot is required.

**Trap 3 — DELETE of a role in use silently deletes its users.**
Splunk refuses users without a role. So deleting a user's last
role deletes the **user** and their private resources (saved
searches, private dashboards). No warning, no confirmation.

**Consequence for governance.**

- Full REST snapshot **before any structural modification**.
- **Mandatory** GET → merge → full POST pattern for role
  modifications.
- **Two-step role migration**: (1) create the new role,
  (2) reassign the users, (3) only then delete the old one.

## SAML family

### F-SAML-01 — `defaultRolesIfMissing` is a fallback, not a floor

**Hypothesis.** The `defaultRolesIfMissing` parameter of
`authentication.conf` might seem to be a "floor role" stacked with
the mapped roles.

**Test and observation.** `defaultRolesIfMissing` is strictly a
**fallback** — it applies only when the IdP emits no mapped group.
A user with at least one mapped group receives **only** the mapped
roles, without the fallback accumulating.

**Consequence for governance.** For a floor role (`role_floor`)
assigned to every authenticated user, the path is to explicitly
map an "all-users" IdP group to `role_floor` via `roleMap_`, **not**
to use `defaultRolesIfMissing`.

**Critical guardrail.** **Never** put `admin` in
`defaultRolesIfMissing`. Splunk temporarily uses `admin` while
processing SAML group information — a fallback to `admin` opens
the door to an **accidental privilege escalation**. Always
`role_no_access` or an equivalent minimal role.

### F-SAML-02 — Auto-mapping and group homonymy

**Observation.** Auto-mapping (`enableAutoMappedRoles=true`)
triggers the assignment of a Splunk role if the IdP emits a group
whose name is **exactly equal** to the role (lowercase). Convenient
for high volume but opens a risk of **accidental homonymy**: if a
directory group happens to have a name matching a sensitive role
(`admin`, `admin_ops`), the user may be granted that role.

**Consequence for governance.** **Never** auto-map administrative
roles. Always combine:

```ini
[saml]
enableAutoMappedRoles = true
excludedAutoMappedRoles = admin;admin_iam;admin_ops
roleMap_<authSettings> = admin_iam:splunk_admin_iam;admin_ops:splunk_admin_ops;role_floor:splunk_all_users
```

### F-SAML-03 — No wildcard on groups

**Observation.** Splunk 9.4 treats the `roleMap_*` value **as a
literal string**. No wildcard on the group side: `role_floor:*`
assigns `role_floor` to nobody.

**Consequence.** The floor role necessarily goes through an
explicit "all-users" IdP group mapped to `role_floor`.

## WLM family

### F-WLM-01 — Every category requires a default pool

**Documented hypothesis.** The Splunk documentation describes
`default_category_pool=1` as an option for designating the default
pool of a category. A careful reader would understand that at
least one is needed per category in use.

**Test run.** Configure a `search` category with its five business
pools (`admin`, `scheduled`, `ad_hoc`, `bulk`, `accel`), a single
`default_category_pool=1` on `ad_hoc`. The `ingest` and `misc`
categories exist but with no default pool. Enable WLM via
`workload-management-status enabled=1`.

**Observed result.** Activation **silently fails**. The toggle
stays at `0`. `splunkd.log` shows an initialization error pointing
to the missing `default_category_pool=1` on the `ingest` and
`misc` categories.

**Additional test.** Add `ingest_default` and `misc_default` with
`default_category_pool=1` in `ingest` and `misc`. Activation
succeeds.

**Consequence for governance.** The nominal design must include
**seven pools**:

- five business pools in `search` (`admin`, `scheduled`, `ad_hoc`,
  `bulk`, `accel`);
- one default pool in `ingest` (`ingest_default`);
- one default pool in `misc` (`misc_default`).

The two default pools of the non-business categories get a
minimal weight (1 % each in `cpu_weight` and `mem_weight`); they
exist only to allow activation.

### F-WLM-02 — Implicit placement, not `action=workload_pool`

**Hypothesis.** A quick read of the docs might suggest an
`action = workload_pool` for placement (by analogy with
`action = abort`, `action = move`).

**Test run.** A `workload_rule` with `action = workload_pool` and
`workload_pool = scheduled`.

**Observed result.** splunkd rejects: "invalid action
`workload_pool`". The valid actions are `move`, `abort`, `alert`,
`filter`, `queue`.

**Real behavior.** Placement is **implicit**: the mere presence of
the `workload_pool = <pool>` key in a `[workload_rule:*]` that
matches **without** an `action=` key is enough to route the search
to the named pool.

**Consequence for governance.** Any internal documentation
mentioning `action=workload_pool` must be corrected. Placement is
implicit.

### F-WLM-03 — `runtime>` is mandatory for `abort/move/alert`

**Observation.** Monitoring actions (`abort`, `move`, `alert`) are
evaluated **at runtime**, every ten seconds. For a `workload_rule`
to trigger them, its predicate **must** include a `runtime>` bound
(for example `runtime>1s`, `runtime>1m`). Otherwise splunkd
refuses the rule at activation with an explicit error.

**Consequence for governance.** Every monitoring rule carries a
minimal `runtime>` bound, even symbolic (`runtime>1s` is enough to
activate the mechanism). Pure **placement** rules do not need
one.

### F-WLM-04 — `action = display_message` does not exist

**Documented hypothesis.** The Splunk 9.4 documentation on
workload rules mentions `display_message` as an action value
enabling a "notification without constraint" mode — the search
runs, a message is displayed.

**Test run.** A `workload_rule` with `action = display_message`.

**Observed result.** splunkd **rejects** the rule: "Valid actions
are `move`, `abort`, `alert`, `filter`, and `queue`." The
`display_message` value **does not exist** on 9.4.6.

**Functional equivalent.** `action = alert`. The search continues,
an event is written to `_audit`, a structured message appears in
the job inspector. It is the native equivalent of a
**per-rule monitor-only mode**.

**Consequence for governance.** **Every** monitor-only WLM
rollout uses `action = alert`. Any internal documentation
mentioning `display_message` must be corrected. This finding alone
saves a team that would try to deploy on the strength of the docs
several days of debugging.

### F-WLM-05 — `[workload_rules_order]` accepts only `[workload_rule:*]`

**Observation.** Evaluation order is defined in
`[workload_rules_order]` by a `rules = rule_A, rule_B, …` key.
Trying to list a `[search_filter_rule:*]` (admission rule) in
there produces an HTTP 404 at activation. Admission rules are
evaluated **in parallel**, with no order.

**Consequence.** The order concerns workload rules only.
Admission rules are not ordered — it suffices for one to match
`filter` to block.

### F-WLM-06 — `user_message` of admission rules: syntax constraints

**Observation.** The `user_message` field of a
`search_filter_rule` (the message returned to the client when the
action is `filter`) carries several constraints empirically
observed on 9.4.6: maximum length around 140 characters, restricted
character set (alphanumerics, spaces, comma, colon, semicolon,
period, underscore, hyphen, apostrophe, double quote), **no
parentheses**. A string with parentheses gets the rule rejected.

**Consequence.** Write `user_message` as simple sentences without
parentheses. Use colons or hyphens to structure if needed.

### F-WLM-07 — Hot-reload on the search head, restart on the indexer

**Observation.** On a search head, modifying `workload_pools.conf`
or `workload_rules.conf` and then calling
`POST /services/workloads/config/_reload` reloads the configuration
without interruption.

On a peer indexer in a cluster, propagation goes through the
**cluster manager** (`splunk apply cluster-bundle`) which
**restarts the peers** (rolling restart). No hot-reload on the
indexer side for WLM bundles.

(Note for FR-vs-EN readers: the cluster manager was historically
called the cluster master; Splunk renamed it for language
neutrality. Both terms refer to the same component.)

**Consequence for governance.** On a search head, the iteration
cycle is fast (modify + reload). On an indexer cluster, every WLM
bundle modification implies a rolling restart — to be scheduled
outside critical hours.

### F-WLM-08 — Splunkd restart must run as root directly

**Observation.** On the first WLM rollout, a restart of splunkd
is required so that it attaches its processes to cgroups. On a
systemd install, the restart **must** be done as root directly
(`systemctl restart Splunkd`), **not** through
`runuser -u splunk -- splunk restart`, which silently fails with
"Access denied" on systemd-managed services.

**Consequence.** Every WLM rollout procedure must make this
explicit. Automation tooling must use `systemctl` on the service
side, not the `splunk` wrapper on the binary side.

## App ACL family

### F-ACL-01 — Active inheritance of object ACLs via `importRoles`

**Observation.** An object ACL placed on a parent role
(`perms.read=role_parent`) is **inherited** by child roles that
import that parent via `importRoles`. The object ACL layer is
evaluated against the effective set of roles, **imported roles
included**.

**Consequence for governance.** App and knowledge-object ACLs can
(and should) reference the **`app_*` atomics**. Composites that
import them automatically get access. This is what makes the
atomic/composite pattern coherent all the way down to the ACL
layer.

## Findings summary table

| Code | Family | Real 9.4.6 behavior |
| --- | --- | --- |
| F-RBAC-01 | RBAC | Inherited capability non-revocable, `=disabled` is a silent no-op |
| F-RBAC-02 | RBAC | Quotas not inherited in the enforcement sense, multi-role `max()` |
| F-RBAC-03 | RBAC | `srchIndexesAllowed=*` does not cover internals `_*` |
| F-RBAC-04 | RBAC | `srchIndexesDisallowed` takes precedence, inherits, most-restrictive multi-role |
| F-RBAC-05 | RBAC | `-_audit` / `!_audit` syntax invalid (no-op) |
| F-RBAC-06 | RBAC | `srchFilter` combines with OR multi-role, `*` nullifies everything |
| F-RBAC-07 | RBAC | App ACL `write` without `read` = invisible (404) |
| F-RBAC-08 | RBAC | POST = destructive SET; DELETE built-in breaks `admin`; DELETE in-use role deletes users |
| F-SAML-01 | SAML | `defaultRolesIfMissing` is a fallback, not a floor; never `admin` |
| F-SAML-02 | SAML | Auto-mapping homonymy risk; `excludedAutoMappedRoles` mandatory for `admin_*` |
| F-SAML-03 | SAML | No wildcard on groups; floor role via explicit "all-users" group |
| F-WLM-01 | WLM | Every category (`search`, `ingest`, `misc`) requires a `default_category_pool=1` |
| F-WLM-02 | WLM | Implicit placement via `workload_pool=`, not `action=workload_pool` |
| F-WLM-03 | WLM | `runtime>` mandatory for monitoring actions (`abort`/`move`/`alert`) |
| F-WLM-04 | WLM | `action=display_message` does not exist; use `action=alert` |
| F-WLM-05 | WLM | `[workload_rules_order]` accepts only `[workload_rule:*]` |
| F-WLM-06 | WLM | `user_message`: ~140 chars, no parentheses |
| F-WLM-07 | WLM | Hot-reload on SH; restart on indexer via cluster-bundle |
| F-WLM-08 | WLM | Splunkd restart as root directly (`systemctl`), not via `runuser` |
| F-ACL-01 | ACL | Active inheritance of object ACLs via `importRoles` |

## How to use these findings

These findings are **defensible**. A Splunk practitioner who
encounters a technical decision that disagrees with one of these
points can cite the finding by its code and its test, and trigger
a verification on the real 9.4.6 binary.

This is the chapter's main value: none of these behaviors can be
deduced from a plain reading of the official documentation. They
can only be discovered by a maquette.

## Sources

- [Splunk Securing 9.4 — Roles and capabilities](https://help.splunk.com/en/splunk-enterprise/administer/secure-splunk-enterprise/9.4/define-roles-on-the-splunk-platform/about-defining-roles-with-capabilities)
- [Splunk Admin 9.4 — authorize.conf](https://help.splunk.com/en/data-management/splunk-enterprise-admin-manual/9.4/configuration-file-reference/9.4.5-configuration-file-reference/authorize.conf)
- [Splunk Admin 9.4 — authentication.conf](https://help.splunk.com/en/data-management/splunk-enterprise-admin-manual/9.4/configuration-file-reference/9.4.5-configuration-file-reference/authentication.conf)
- [Splunk Workload Management 9.4 — Configure workload rules](https://help.splunk.com/en/splunk-enterprise/administer/manage-workloads/9.4/configure-workload-management/configure-workload-rules)
- [Splunk Workload Management 9.4 — Configure admission rules](https://help.splunk.com/en/splunk-enterprise/administer/manage-workloads/9.4/configure-workload-management/configure-admission-rules-to-prefilter-searches)
