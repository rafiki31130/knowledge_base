# Change plans

Generic, technology-focused change plan **templates**. Each fiche describes a
class of change (not a specific instance), with the pieces you will need
regardless of the target environment: what the change is, the risks it
carries, the steps to run it, how to roll it back, and how to confirm it
worked.

These fiches are written in **English** by convention — change plans tend to
circulate in heterogeneous teams.

## What goes here

- A class of change on a well-known technology (e.g. "Splunk indexer cluster
  site id change", "Elasticsearch rolling restart", "PostgreSQL major version
  upgrade").
- Generic placeholders only (`indexer-01`, `<old_site>`, `<cluster-manager>`).
  Anything that would tie the fiche to a real environment goes into an
  internal wiki, not here.

## What does not go here

- A change request for a specific environment / customer / ticket.
- Detailed values (hostnames, IPs, RF/SF numbers, bucket counts) from a real
  deployment.
- Run logs, post-change reports, incident timelines.

If a change plan only makes sense with real values filled in, it belongs in
the operational wiki, not this public knowledge base.

## Structure of a change plan

Every fiche follows the same skeleton, in this order:

1. **Generic description of the change** — what is being changed and why this
   kind of change is run. Written as a template the reader adapts to their
   own context.
2. **Risks and service interruption** — what can go wrong, what is degraded
   during the change, expected user-visible impact.
3. **Change plan** — ordered, verifiable steps to execute the change. Open it
   with a **step-overview table** (see Conventions below), then one block per
   step.
4. **Rollback plan** — how to return to the pre-change state, with the
   decision criteria for triggering rollback. Same shape as the change plan:
   a step-overview table, then config-first steps.
5. **Validation plan** — checks that prove the new state is healthy, ideally
   distinct from the checks already done inside the change steps.
6. **Open reservations** — items the reader **must** clarify before running
   the plan in a real environment. These exist because the fiche is generic
   and was written without the full technical context of any specific
   deployment.

The "Open reservations" section is mandatory: a generic change plan is never
ready to run as-is, and explicitly listing what needs to be checked locally
prevents readers from treating the fiche as a copy-paste runbook.

## Conventions

- File naming: `kebab-case.md`, descriptive of the change class
  (`splunk-indexer-cluster-site-id-change.md`).
- Placeholders use angle brackets: `<old_site>`, `<cluster-manager-host>`,
  `<rf>`, `<sf>`.
- **Step-overview table first.** Every change plan and rollback plan opens with a
  short table the reader can grasp before reading any detail — one row per step,
  columns: `#` · node/component · what changes · config file/stanza touched ·
  action (restart, run X…). The reader sees the whole sequence at a glance, then
  drops into the per-step detail.
- **Config-first, commands second.** Express each step as the **target
  configuration** — show the config file/stanza with the lines to set and an
  inline annotation (`CHANGED` / `ADDED` / `REMOVED` / `unchanged`, with the old
  value noted), so the reader knows the desired end state independently of any
  tool. Commands (CLI, `sed`, config-management) are how you *apply* that state and
  come after, kept minimal. Reserve full command blocks for genuine actions that
  aren't config (graceful shutdowns, restarts, verification queries).
- When a step edits a file that also holds a secret, the plan must say to touch
  **only** the lines shown and never rewrite the secret-bearing stanza wholesale.
- Vendor documentation links use the full HTTPS URL (no internal redirects).

## Existing change plans

- [Splunk multisite cluster — in-place site id rename](./splunk-indexer-cluster-site-id-change.md)
  — lab-validated method (`splunk offline` + `site_mappings`), with the
  experiment results that justify it.
