# Splunk Usage Governance — A Practitioner's Handbook

> 🇫🇷 **Version française disponible** : [`../README.md`](r_knowledge_base_pro/handbooks/gouvernance-utilisateurs-splunk/README.md)

> A handbook for establishing comprehensive usage governance on a medium-
> to-large Splunk Enterprise Search Head Cluster (SHC), serving hundreds
> to thousands of users. The handbook consolidates a method, an
> authorization model, an awareness program, a Workload Management
> framework, and a body of empirical findings gathered on Splunk
> Enterprise 9.4.6.

## Note on the French-to-English mapping

This handbook was originally written in French. The English version
lives in this `EN/` subfolder and mirrors the French version
chapter-for-chapter. File names have been adapted to be idiomatic in
English rather than transliterated. The mapping is:

| Source (FR) | This version (EN) |
| --- | --- |
| `README.md` | `EN/README.md` |
| `01-pourquoi-gouverner.md` | `EN/01-why-governance.md` |
| `02-methode-projet.md` | `EN/02-project-method.md` |
| `03-quatre-axes.md` | `EN/03-four-axes.md` |
| `04-findings-empiriques.md` | `EN/04-empirical-findings.md` |
| `05-guide-rbac.md` | `EN/05-rbac-guide.md` |
| `06-guide-wlm-sh.md` | `EN/06-wlm-search-head-guide.md` |
| `07-guide-wlm-indexers.md` | `EN/07-wlm-indexers-guide.md` |
| `08-recommandations-chiffrees.md` | `EN/08-recommendations.md` |

The French version remains canonical. If the two versions ever
diverge, the French version is the source of truth.

## Who this handbook is for

- **Splunk architects** who need to scope or rebuild governance on an
  existing SHC.
- **Senior Splunk sysadmins** who inherit a platform with no documented
  model and have to decide what to do with it.
- **Technical project managers** running a compliance or hardening
  initiative who want a repeatable method.

Implicit prerequisites: you know what a Search Head Cluster is, you
can read an `authorize.conf` without effort, you have already deployed
a Splunk app, you understand what `srchJobsQuota` caps and what a
saved search is. This handbook does not teach Splunk — it teaches how
to **govern** Splunk usage at scale.

## What this handbook covers

- **Why** a usage-governance project is necessary, and the warning
  signs that point to it (chapter 1).
- **How** to run a governance project: scoping method, empirical lab
  maquette, independent audit, handbooks (chapter 2).
- **Four structuring axes** that compose together: hardening default
  rights, a hybrid authorization model, pedagogical awareness,
  Workload Management (chapter 3).
- **Empirical 9.4.6 findings**, documented and defensible: a
  non-revocable inherited capability, inherited quotas that don't
  enforce, the multi-role `max()` rule, a `display_message` action
  that does not exist, write-without-read app ACLs that make objects
  invisible, and other traps (chapter 4).
- **Operational guides** per axis (chapters 5 through 7): RBAC audit,
  progressive RBAC design, WLM audit, WLM design, indexer-side
  considerations.
- **Numeric recommendations** drawn from the state of the art
  (chapter 8).

## What this handbook does not cover

- Standing up and operating an SHC (`Distributed Deployment Manual`).
- Day-to-day SPL writing — see the
  [Splunk Power-User Handbook](r_knowledge_base_pro/handbooks/splunk-user-handbook/README.md)
  in this repo for analyst-side good practices.
- Cloud, SOAR, Observability, ES, or ITSI topics.
- Integration details for any specific IdP (ADFS, Entra ID, Okta) —
  we stay IdP-agnostic and call out the invariants.

## How to use it

The handbook is designed to be read **sequentially** on first pass:
the method (chapter 2) frames the axes (chapter 3), which motivate
the findings (chapter 4), which in turn justify the operational
guides (chapters 5 through 7).

After that first pass, each chapter reads independently. Chapters 5
through 8 are the reference chapters you reopen at the moment of a
concrete action. Chapter 4 (findings) is the chapter you cite to
defend a technical decision against a poorly informed counter-proposal.

## Versioning and assumptions

This handbook is written against **Splunk Enterprise 9.4.6** on-prem,
in a Search Head Cluster topology with shared indexers. Empirical
findings carry the 9.4.6 tag where they have been observed. When a
later minor release on the 9.4 branch changes a documented behavior,
chapter 4 will flag it.

The reference archetype is an SHC of roughly one thousand users, with
apps split by application production, sharing indexers with other
SHCs. Numeric thresholds and pool percentages are calibrated for that
archetype. They should be adapted to context — every numeric
recommendation carries the caveat "adapt to context."

A note on Splunk terminology: Splunk renamed the `cluster master`
component to `cluster manager` starting with 9.0, for language
neutrality. The function is unchanged; only the name moved. This
English version of the handbook uses `cluster manager` throughout,
which aligns with current Splunk 9.4 documentation. The French
version still uses `cluster master`, which remains in common practice
among French-speaking practitioners. Both terms refer to the same
component.

## Conventions

### Placeholders

To stay anonymized and reproducible, the handbook uses consistent
placeholders across chapters.

| Category | Canonical placeholder |
| --- | --- |
| Operational indexes | `idx_<scope>` (e.g. `idx_network`, `idx_security`, `idx_system`) |
| Business scopes | `<scope>` (e.g. `network`, `security`, `system`) |
| Application productions | `<prod>` (e.g. `<prod>_app`, `app_<prod>`) |
| Atomic roles | `data_<scope>`, `feature_<cap>`, `app_<prod>`, `quota_<tier>` |
| Composite roles | `business_<profile>_<scope>`, `owner_app_<prod>`, `admin_iam`, `admin_ops` |
| Quota tiers | `quota_base`, `quota_plus`, `quota_max` |
| WLM pools | `admin`, `scheduled`, `ad_hoc`, `bulk`, `accel` |
| Hostnames | `sh01`, `idx01`, `cm01`, `ds01` |
| Domains | `example.com`, `corp.example.com` |
| IP / CIDR | `10.0.0.0/24`, `192.0.2.10` (RFC 5737) |
| Users | `alice`, `bob`, `svc_app` |

When an example uses a concrete value (`business_consultative_network`
rather than `business_<profile>_<scope>`), it is a **typed example**
and is not normative. The shape to remember is the generic pattern.

### SPL notation

SPL goes in fenced ```` ```spl ```` blocks. Shell commands go in
```` ```bash ````. Splunk configuration goes in ```` ```ini ```` or
```` ```conf ````.

### Citing sources

Factual claims point to the official Splunk 9.4 documentation when
they draw from it. When a claim has been **observed empirically on a
9.4.6 lab** and diverges from the documentation, chapter 4
(findings) carries the trace.

## Table of contents

| # | Chapter | Topic |
| --- | --- | --- |
| 1 | [Why a governance project](01-why-governance.md) | Symptoms, drift, business stake |
| 2 | [Project method](02-project-method.md) | Scoping → maquette → audit → handbook cycle |
| 3 | [The four structuring axes](03-four-axes.md) | Overview and articulation |
| 4 | [Splunk 9.4.6 empirical findings](04-empirical-findings.md) | Defensible behaviors vs. the documentation |
| 5 | [RBAC guide — audit, design, deployment](05-rbac-guide.md) | Audit, hybrid model, tiers, SAML |
| 6 | [Workload Management guide — search heads](06-wlm-search-head-guide.md) | Pools, rules, monitor-only, enforce |
| 7 | [Workload Management guide — indexers](07-wlm-indexers-guide.md) | `ingest` / `search_peer` categories, cluster manager propagation |
| 8 | [Numeric recommendations and appendices](08-recommendations.md) | Tiers, percentages, glossary, ready-to-use SPL |

## Global sources

The handbook draws on the official Splunk 9.4 documentation:

- [Securing Splunk Enterprise 9.4 — Roles and capabilities](https://help.splunk.com/en/splunk-enterprise/administer/secure-splunk-enterprise/9.4/define-roles-on-the-splunk-platform/about-defining-roles-with-capabilities)
- [Admin Manual 9.4 — Users and roles](https://help.splunk.com/en/splunk-enterprise/administer/admin-manual/9.4/users-and-role-based-access-control)
- [authorize.conf 9.4 spec](https://help.splunk.com/en/data-management/splunk-enterprise-admin-manual/9.4/configuration-file-reference/9.4.5-configuration-file-reference/authorize.conf)
- [authentication.conf 9.4 spec](https://help.splunk.com/en/data-management/splunk-enterprise-admin-manual/9.4/configuration-file-reference/9.4.5-configuration-file-reference/authentication.conf)
- [SAML SSO 9.4](https://help.splunk.com/en/splunk-enterprise/administer/manage-users-and-security/9.4/use-saml-as-an-authentication-scheme-for-single-sign-on)
- [Manage workloads 9.4 — overview](https://help.splunk.com/en/splunk-enterprise/administer/manage-workloads/9.4/workload-management-overview)
- [Configure workload pools 9.4](https://help.splunk.com/en/splunk-enterprise/administer/manage-workloads/9.4/configure-workload-management/configure-workload-pools)
- [Configure workload rules 9.4](https://help.splunk.com/en/splunk-enterprise/administer/manage-workloads/9.4/configure-workload-management/configure-workload-rules)
- [Configure admission rules to prefilter searches 9.4](https://help.splunk.com/en/splunk-enterprise/administer/manage-workloads/9.4/configure-workload-management/configure-admission-rules-to-prefilter-searches)
- [Splunk Lantern — limit features that can impact platform performance](https://lantern.splunk.com/)
- [NIST SP 800-63B — Digital Identity Guidelines](https://pages.nist.gov/800-63-3/sp800-63b.html) (IAM lifecycle)
