# Splunk Power-User Handbook

> A short book of reflexes for the Splunk power user who already writes SPL, already saves dashboards, already builds alerts — and wants to stop relearning the same lessons the hard way.

## What this handbook is and isn't

**Is.** A consolidated set of major good practices, anti-patterns to ban, and explicit escalation triggers, organized around four axes: SPL, dashboards and visualizations, alerts and scheduled searches, and apps / knowledge objects / RBAC. A chapter 0 anchors the mental models the rest of the book assumes; a closing cheatsheet aggregates every escalation trigger in one printable page.

**Isn't.** A tutorial. A "what is Splunk" introduction. An admin manual. A SPL2 reference. A Splunk Cloud guide. If you need any of those, this is not the right book.

## Persona

You are a SecOps or IT power user. You write `index=… sourcetype=… | stats … by …` from memory. You know the time picker, the dashboard editor (Studio or Classic), and the alert wizard. You do not have admin rights: you cannot edit `$SPLUNK_HOME/etc/system/local/`, you do not own `props.conf` or `transforms.conf`, you cannot grant capabilities or add indexes. You have committed all the anti-patterns in this book at least once.

## Scope

- **Splunk Enterprise 9.x on-prem, with examples pinned to 9.4.**
- **SPL1 only.** No SPL2.
- **No Splunk Cloud-only features**, no Splunk Observability, no SOAR.
- **English only** for this edition. A French translation may follow later as a separate project.

## How to use this handbook

Every chapter is independent. The proposed order is pedagogical, not mandatory: start at Foundations if the mental models are not solid, otherwise jump straight to the axis you need. Every chapter ends with a "When to escalate to an admin" section; if you are short on time, [`99-escalation-cheatsheet.md`](99-escalation-cheatsheet.md) consolidates all of them into a single reference.

## Table of contents

| # | Chapter | Status |
| --- | --- | --- |
| 0 | [Foundations — how Splunk thinks](00-foundations.md) | Available |
| 1 | [SPL — anatomy of a good search](01-spl-search-anatomy.md) | Available |
| 2 | [SPL — `stats`, transforming commands and the `\| stats` mindset](02-spl-transforming-and-stats.md) | Available |
| 3 | [SPL — correlating events: joins, subsearches, lookups](03-spl-correlation-joins-lookups.md) | Available |
| 4 | [SPL — acceleration: `tstats`, summary indexing, data models](04-spl-acceleration-tstats-datamodels.md) | Available |
| 5 | [Dashboards and visualizations](05-dashboards-and-visualizations.md) | Available |
| 6 | [Alerts and scheduled searches](06-alerts-and-scheduled-searches.md) | Available |
| 7 | [Apps, knowledge objects, sharing and RBAC](07-apps-knowledge-objects-rbac.md) | Available |
| 99 | [When to escalate to an admin — consolidated cheatsheet](99-escalation-cheatsheet.md) | (coming soon) |

## Conventions

### Placeholders

All examples use the same canonical placeholders so the same shape of search keeps reading the same way across chapters.

| Category | Canonical value |
| --- | --- |
| Operational indexes | `main`, `os`, `network`, `security` |
| Sourcetypes | `linux_secure`, `cisco:asa`, `access_combined`, `WinEventLog:Security` |
| Hostnames | `web01`, `db01`, `idx01`, `sh01`, `ds01` |
| Users | `alice`, `bob`, `svc_app` |
| Roles | `analyst`, `ops_l2`, `app_owner_payments` |
| Custom apps | `my_company_app`, `payments_dashboards` |
| Domains | `example.com`, `corp.example.com` |
| IP / CIDR | `10.0.0.0/24`, `192.0.2.10` (RFC 5737), `2001:db8::/32` |
| Lookups | `users.csv`, `assets.csv` |
| Macros | `get_internal_traffic`, `time_business_hours` |

### Command notation

- SPL examples live in fenced ```` ```spl ```` blocks. Multi-command pipelines are written one command per line with `|` at the start of each continuation line.
- UI gestures are written as paths: "Settings → Searches, reports and alerts → New Alert".
- Time ranges are always explicit (`earliest=-24h@h latest=now`) unless the prose specifies the window in plain English.

### Sources

Factual claims point inline to the canonical Splunk documentation, with URLs pinned to the 9.4 manuals (`docs.splunk.com/Documentation/Splunk/9.4/...`). Splexicon is cited for definitions only, never as evidence of command behavior. Each chapter ends with a `## Sources` section that consolidates its citations.

## Global sources

The handbook draws primarily on the official Splunk documentation, frozen on 9.4:

- [Search Manual (9.4)](https://docs.splunk.com/Documentation/Splunk/9.4/Search/WhatsInThisManual)
- [Search Reference (9.4)](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/WhatsInThisManual)
- [Knowledge Manager Manual (9.4)](https://docs.splunk.com/Documentation/Splunk/9.4/Knowledge/WhatsInThisManual)
- [Dashboards and Visualizations — Studio (9.4)](https://docs.splunk.com/Documentation/Splunk/9.4/DashStudio/Overview) and [Classic SimpleXML (9.4)](https://docs.splunk.com/Documentation/Splunk/9.4/Viz/AboutdashboardsandSimpleXML)
- [Alerting Manual (9.4)](https://docs.splunk.com/Documentation/Splunk/9.4/Alert/Aboutalerts)
- [Admin Manual (9.4)](https://docs.splunk.com/Documentation/Splunk/9.4/Admin/Aboutusersandroles) and [Securing Splunk Enterprise (9.4)](https://docs.splunk.com/Documentation/Splunk/9.4/Security/Rolesandcapabilities)
- [Common Information Model](https://docs.splunk.com/Documentation/CIM/latest/User/Overview)
- [Splexicon](https://docs.splunk.com/Splexicon)

Complementary sources (Splunk blog, Splunk Lantern) are accepted as context only; they never carry an isolated normative claim.

## Versioning note

This handbook is written against **Splunk Enterprise 9.4** (latest 9.x stable at the time of writing), SPL1, on-prem. Where 9.x minor versions differ on a specific behavior, the chapter says so explicitly.
