# Chapter 7 — Apps, knowledge objects, sharing and RBAC

> Your saved search works for you and not for your colleague. Your dashboard is "shared" but nobody else can open it. A macro you wrote yesterday is suddenly resolving to a different SPL today. None of these are bugs — they are the predictable consequences of where knowledge objects live, which app context resolves them, and which role-based access control (RBAC) layer gates them. This chapter pins down the rules so you stop guessing, and draws the line where your power as a non-admin stops.

## Quick refresher

Eight ideas keep the rest of the chapter unambiguous.

- **App.** A container of knowledge objects (KO) plus a permissions envelope. `Search & Reporting` is the default app; `my_company_app` is what a team app looks like. An app lives on disk under `$SPLUNK_HOME/etc/apps/<app>/` and ships `default/` (admin-shipped defaults) and `local/` (your overrides). You only ever write into `local/`, and most of the time you do it through the UI.
- **Knowledge object.** Anything savable that is not raw data: **saved searches, dashboards, macros, tags, eventtypes, field extractions, lookup definitions, data models, alerts**. Every KO is born inside one app and inherits its sharing.
- **Sharing scope.** Three values: **Private** (owner only), **App** (everyone with access to the parent app), **Global** (everyone, every app). A Private KO lives in `$user/local/`; an App or Global KO lives in `$app/local/` with a `.meta` file declaring the scope.
- **Role and capability.** A **role** bundles capabilities (`search`, `schedule_search`, `rest_apps_view`, …) and index access (`srchIndexesAllowed`, `srchIndexesDefault`). A user gets the **union** of all their roles' capabilities and the **union** of their indexes. Inheritance is additive — there is no negative permission.
- **App context resolution.** When you run SPL, Splunk resolves macros, eventtypes, tags, and lookups **through the current app**, walking app exports and Global-shared KO. Switching the app in the search bar changes the resolution silently.
- **`.meta` files.** Per-app ACL files that declare ownership and sharing for each KO. You rarely edit them by hand; the Permissions dialog writes them for you.

## Major good practices

1. **Default new KO to App-scope in the right app.** A Private KO rots: it dies with your account and nobody else can call it. A Global KO pollutes every app and creates name collisions with Splunkbase add-ons. App scope is the right default for anything you would not be embarrassed to put your name on. Pick the app where the data and the rest of the use case live — if you are searching `index=security` for the SOC, the SOC app is the right home. See [Knowledge Manager Manual — Manage knowledge object permissions](https://docs.splunk.com/Documentation/Splunk/9.4/Knowledge/Manageknowledgeobjectpermissions).
2. **Name KO with a stable prefix that identifies the team or app.** `payments_failed_logins`, `soc_dns_exfil_top_talkers`, `ops_l2_disk_pressure`. Two reasons: it survives moving the KO between apps without losing its semantics, and it eliminates name collisions when a Splunkbase add-on installs a saved search called `failed_logins`. Convention beats ingenuity: pick a prefix per team and stick to it.
3. **Use macros for any SPL fragment you would otherwise copy-paste.** The moment you write the same `eval`/`rex`/`lookup` chain in three searches, extract it into a macro with arguments — `\`get_internal_traffic(src_ip)\`` reads better, evolves in one place, and lets you fix a bug across every consumer at once. Macros are KO like any other: they have an app context, a sharing scope, and a permissions envelope. Document the arguments in the macro description.
4. **Use tags and eventtypes to encode semantics once, not per search.** An eventtype is a named base search; tagging the eventtype attaches a domain label. Once `eventtype=authentication_failure` is defined and tagged `authentication`, any chapter-1 reflex (`index=… eventtype=authentication_failure | stats count by user`) carries the semantics without redefining the regex in every saved search. Splunk Common Information Model (CIM) is built on this pattern; if you find yourself reinventing it, check CIM first.
5. **When you inherit someone's KO, re-own it, re-verify permissions, re-test the search.** A KO whose owner has left the org becomes an orphan: ACL changes go through whoever inherits, scheduled searches still tick under the gone user, and audit trails point nowhere. Use the UI Permissions dialog to `chown` to yourself (or a service principal), then re-verify scope and re-run the search to confirm it still resolves macros and lookups in your current app context.
6. **Write a one-sentence description on every KO.** The Description field shows up in `rest /services/saved/searches` listings, in the saved-search picker, and to whoever inherits your work two years from now. "Top failed-login source IPs over 15 minutes, used by SOC on-call" is the difference between a maintainable KO and an archaeology project.
7. **Know which app you are in before you save anything.** The save dialog defaults to the **current app context**, not to whatever app the underlying index "belongs" to. Saving a SOC search while you happened to be inside `my_company_app` because of a side-quest creates a shadow KO inside the wrong app, and the SOC team cannot find it. Glance at the breadcrumb before you click Save.

## Anti-patterns to ban

1. **`Global` sharing because "it is easier".** You have just exported your bug — and your future renamings — to every app on the search head. Global is for genuinely shared primitives (CIM tags, a vetted enrichment lookup), not for "I do not want to think about which app this belongs to". When in doubt, use App and let the explicit boundary force the right conversation.
2. **KO owned by an individual who has left.** Orphan KO accumulate silently: scheduled searches keep running under a disabled account until the scheduler complains, dashboards keep failing for the team that inherited them. Run a periodic sweep (`| rest /services/saved/searches | search eai:acl.owner=<leaver>`) and either re-own or delete.
3. **Twelve variants of the same search instead of one parameterized macro.** `failed_logins_24h`, `failed_logins_1h`, `failed_logins_by_src`, `failed_logins_by_user` — every variant is a fork that drifts. One macro `\`failed_logins(window, by_field)\`` and four saved searches that call it gives you the same result with one piece of logic to maintain.
4. **Editing a KO in the wrong app context — and creating a silent shadow in `$user/local/`.** If you save changes to an App-scope KO while you have permissions only to its Private variant, Splunk creates a Private shadow in `$user/local/` that overrides the App version *for you*. You see the new behavior; nobody else does. When a teammate insists "my search has not changed and yours is broken", check whether one of you has a Private shadow.
5. **Asking an admin for index access for a one-off.** Index access is an org-level change with a long blast radius. Before raising the request, check whether a published lookup, a Global-scope macro, or a `tstats summariesonly=t` against an accelerated data model would answer the same question without granting you persistent read on a new index.
6. **Building tags or eventtypes that collide with Splunkbase apps you also use.** Installing `Splunk_TA_nix` ships an `eventtype=linux_secure` and a set of tags; defining your own `linux_secure` eventtype in `my_company_app` creates a resolution war whose winner depends on app context. Check `| rest /services/saved/eventtypes | search title=<name>` before you commit to a name.
7. **Saving a personal Private KO and forgetting it exists.** A Private saved alert that triggers every five minutes is invisible to your team — they will not see it in the scheduler view, they will not see the noise it generates in downstream channels. If you are the only one who needs it, it probably should not be a scheduled alert; if a team needs it, it should not be Private.

## Worked examples

### Refactor four saved searches into one macro plus parameterized calls

Before: four near-identical saved searches.

```spl
index=security sourcetype=linux_secure action=failure earliest=-24h@h latest=now
| stats count by user
```

```spl
index=security sourcetype=linux_secure action=failure earliest=-1h@h latest=now
| stats count by user
```

```spl
index=security sourcetype=linux_secure action=failure earliest=-24h@h latest=now
| stats count by src_ip
```

```spl
index=security sourcetype=linux_secure action=failure earliest=-1h@h latest=now
| stats count by src_ip
```

After: one macro `failed_logins(window, by_field)` defined in the SOC app with App-scope sharing, two arguments, and a description that explains the contract.

```spl
index=security sourcetype=linux_secure action=failure earliest=-$window$ latest=now
| stats count by $by_field$
```

Each of the four saved searches now reads `\`failed_logins(24h@h, user)\`` (or the variant). When the SOC asks you to add `host` to the breakdown, you change one place. When the SOC asks you to also count successes, you add a third argument with a default value and the callers do not change. Mark the macro with `validation` so Splunk warns you if a caller passes an argument that does not match.

### Transfer dashboard ownership when someone leaves

Bob owned `dash_payments_overview` in `payments_dashboards`, sharing **App**. Bob leaves. Today the dashboard renders but every change you propose through the UI is refused with "you do not have write permissions on this object". The reason: write ACL is granted to the **owner** plus the roles listed in `.meta`. Bob is gone, you are not in the writer roles.

Steps that actually work, in this order:

1. From the admin (one-time cost, not yours to skip): list orphan KO with `| rest /services/saved/searches /services/data/ui/views | search eai:acl.owner=bob`.
2. The admin (or you, if your role has the `admin_all_objects` capability — usually it does not) re-owns the KO to a service principal like `svc_app`, not to a person.
3. You are added to the writer roles in the Permissions dialog for the specific KO, or — better — a role like `app_owner_payments` is granted write on App-scope objects of `payments_dashboards`.
4. You re-test the dashboard end to end, especially any panel that relied on a Private macro Bob owned: those died with him.

The wider lesson: **never own a production KO with a personal account**. Re-own to a service principal as a matter of routine, not as a leaver-day scramble.

### Encode "internal traffic" once with a tag plus an eventtype

A team writes ten searches that all begin with the same filter:

```spl
index=network ( src_ip=10.0.0.0/24 OR src_ip=192.0.2.0/24 ) NOT src_ip=10.0.0.99
| ...
```

Replace the boilerplate with an eventtype `internal_traffic` defined in `my_company_app`, App-scope, plus the tag `internal`. The searches become:

```spl
index=network eventtype=internal_traffic
| ...
```

Now the filter lives in **one** place. When networking adds a new internal CIDR, you update the eventtype definition; every consumer picks it up at next dispatch. If the SOC wants to invert the filter for an outbound audit, `index=network NOT eventtype=internal_traffic` reads exactly like English. The same pattern is how the Splunk CIM ships `eventtype=authentication`, `eventtype=malware_attack`, and so on — by ancestry rather than by copy-paste.

## When to escalate to an admin

- **You need a new role, or a new capability added to an existing role.** Roles and capabilities are defined in `authorize.conf` on the search head tier (or on the deployer for a search head cluster). Ask for: "add capability `schedule_search` to role `app_owner_payments`, justification: scheduled alerts for the payments overview dashboard, blast radius limited to `index=payments_*`". Bring the search head, the role, the capability, and the use case in one sentence.
- **You need index access for a role** (`srchIndexesAllowed`, `srchIndexesDefault`). Index access is admin-only and irrevocable from your side. Ask for: "grant role `analyst` read on index `network`, justification: investigations require correlating endpoint events with NetFlow over the last 30 days, expected query cadence: ad-hoc, average 5 searches/day". Mention any existing summary index that could substitute if full access is not warranted. See [Admin Manual — About users and roles](https://docs.splunk.com/Documentation/Splunk/9.4/Admin/Aboutusersandroles).
- **You need a new app deployed**, custom or from Splunkbase. Apps land on a search head cluster through the **Deployer** and on universal forwarders through the **Deployment Server**. Power users do not push to either. Ask for: "deploy `my_company_app` v1.2.3 to SHC `shc-prod` and to UF serverclass `infra`, change ticket: …, rollback plan: revert to v1.2.2 by re-applying the previous bundle". Provide the app tarball or the Splunkbase URL plus the exact version.
- **A KO you defined conflicts with a Splunkbase add-on** — same name, different SPL, last-loaded wins. Ask for: "resolve KO name collision between `my_company_app/eventtype/linux_secure` and `Splunk_TA_nix/eventtype/linux_secure`, propose: rename the local eventtype to `mycorp_linux_secure` and update consumers". This is admin-scoped because the resolution may touch app exports in `default.meta`.
- **A KO must be migrated between apps while preserving its ACL.** Moving a saved search from `my_company_app` to `payments_dashboards` is not a UI gesture: it requires editing the `.meta` files of both apps and may break consumers that referenced the old `app::object` path. Ask for: "migrate saved search `payments_failed_logins` from `my_company_app` to `payments_dashboards` preserving permissions and owner `svc_app`, update consumers: dashboard `dash_payments_overview` panel 3". See [Knowledge Manager Manual — Overview](https://docs.splunk.com/Documentation/Splunk/9.4/Knowledge/Whatisknowledgemanagement).
- **A teammate has effective permissions you cannot explain.** Role union, capability inheritance, and `.meta` overrides interact in ways that are easier to read in `authorize.conf` than to guess from the UI. Ask for: "audit effective capabilities and index access for user `alice` against roles `analyst` + `app_owner_payments`, expected scope vs observed scope: …". Frame it as a fact-finding request, not as a permission complaint.

## Sources

- [Splunk Enterprise 9.4 — Knowledge Manager Manual — Overview](https://docs.splunk.com/Documentation/Splunk/9.4/Knowledge/Whatisknowledgemanagement)
- [Splunk Enterprise 9.4 — Knowledge Manager Manual — Manage knowledge object permissions](https://docs.splunk.com/Documentation/Splunk/9.4/Knowledge/Manageknowledgeobjectpermissions)
- [Splunk Enterprise 9.4 — Admin Manual — About users and roles](https://docs.splunk.com/Documentation/Splunk/9.4/Admin/Aboutusersandroles)
- [Splunk Enterprise 9.4 — Securing Splunk Enterprise — About defining roles with capabilities](https://docs.splunk.com/Documentation/Splunk/9.4/Security/Rolesandcapabilities)
- [Splunk Enterprise 9.4 — Admin Manual — Where to get more apps and add-ons](https://docs.splunk.com/Documentation/Splunk/9.4/Admin/Wheretogetmoreapps)
- [Splexicon](https://docs.splunk.com/Splexicon) — canonical definitions for *app*, *role*, *capability*, *knowledge object*, *app context*, *permissions*.
