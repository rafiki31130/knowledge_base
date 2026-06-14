# Chapter 0 — Foundations: how Splunk thinks

> You already write SPL. You already save dashboards. What slows you down now is not syntax — it is the handful of mental models that decide whether your next search comes back in two seconds or two minutes, and whether the answer you get is the answer you wanted. This chapter pins those models down so the rest of the handbook can stop re-explaining them. Read it once, come back when something surprises you.

## Quick refresher

Keep these eight ideas in working memory; every later chapter assumes them.

- **Index-time vs search-time.** Index-time work — line-breaking, timestamping, sourcetyping, a few indexed fields — runs on the indexer from `props.conf`/`transforms.conf` and is admin-managed. Search-time field extraction runs on the search head from `_raw` and is mostly knowledge-object territory.
- **Events, results, `_raw`.** An **event** is one indexed record with a timestamp and a `_raw` string. After a transforming command, you no longer have events, you have **results**. `_raw` is the source of truth.
- **Indexer / search head / forwarder.** Forwarders ship, indexers store and search, search heads orchestrate. Your surface is the search head; escalations end at the indexer or the forwarder.
- **Dispatch, job, artifact, TTL.** A submitted search creates a **job**, dispatches it, and writes a **dispatch directory** — the **artifact**. The artifact has a **TTL**; when it expires, the job drops out of Job History. Saving bumps the TTL.
- **Search modes.** Fast, Smart, Verbose trade field discovery and event sampling against speed. Defaults differ between the search bar and saved searches.
- **Knowledge object (KO).** Anything savable that is not raw data: saved searches, macros, eventtypes, tags, field extractions, lookups, data models, dashboards, alerts.
- **App context.** Every KO is born inside one app and inherits its sharing (Private / App / Global). This is why your saved search "does not work for your colleague".
- **Version pinning.** SPL behavior drifts between minor versions. This handbook targets **Splunk Enterprise 9.4**, SPL1, on-prem.

## Major good practices

1. **Start in Fast Mode; switch to Smart or Verbose only when you need it.** Fast mode skips field discovery on non-transforming searches and returns less metadata; it is the right default for "let me see what is in there". Move to Smart when you need extracted fields you do not know the names of, and to Verbose only when you must inspect every field and every event. Verbose left on by default is one of the easiest ways to fill a search head's dispatch directory. See [Search Manual — Search modes](https://docs.splunk.com/Documentation/Splunk/9.4/Search/Changethesearchmode).
2. **Scope `index=` and `sourcetype=` before anything else.** Splunk's optimizer is less aggressive than relational engines; the cheapest filters are the ones you put in the base search. Typing `index=os sourcetype=linux_secure host=web01 …` first turns a 30-second search into a 3-second one, and the savings compound across the cluster.
3. **Be deliberate about the time range.** The time picker is the highest-leverage performance lever you have, and it is one click away. "Last 24 hours" beats "All time" by orders of magnitude on a busy index. For saved searches and dashboards, hard-code a tight `earliest`/`latest` instead of inheriting whatever the user last clicked.
4. **Trust `_raw`; treat extracted fields as a hypothesis.** Auto-extracted fields can silently disagree with what is on disk: a malformed regex, an overridden delimiter, or a sourcetype misroute can produce a `user` field that looks plausible and is wrong. When a count surprises you, open one event, expand `_raw`, and compare.
5. **Read the Job Inspector after any search that surprised you.** Slow, empty, weird counts, mysterious duplicates — the Job Inspector tells you which command burned the time, how many events the base search returned, whether you hit a remote-vs-local boundary, and what the normalized search actually was. It is the single most underused tool on a power user's belt. See [Search Manual — Use the Job Inspector](https://docs.splunk.com/Documentation/Splunk/9.4/Search/ViewsearchjobpropertieswiththeJobInspector).
6. **Know which gestures spawn a new job and which reuse the artifact.** Re-submitting the search bar creates a new job. Hitting refresh on a dashboard panel re-runs the panel. Changing the time picker creates a new job. Clicking into a result, going back, and tweaking the SPL by one character creates a new job. Stale dashboards left open for an afternoon can therefore generate dozens of artifacts you never see — they all hit TTL eventually, but the dispatch directory pays for them in the meantime.
7. **Pin the version before trusting any SPL snippet.** "In 9.4, `tstats` accepts X" is a useful sentence; "Splunk supports X" is not. Minor versions ship breaking SPL changes — including default-value tweaks on commands like `timechart` and `stats` — that turn working searches into silently wrong ones after an upgrade.

## Anti-patterns to ban

1. **`index=*` "to see everything".** It scans every index the role can read, saturates indexers, and returns a haystack you cannot sort. If you really do not know where the data lives, ask an admin for the right `index` — they will know — instead of paying the cost of finding out empirically.
2. **`* | search …` instead of `index=… sourcetype=… …`.** Same problem as `index=*`, harder to spot in a code review because the wildcard hides on the left of the pipe. Whenever you see a search that starts with a bare `*`, rewrite the base.
3. **Trusting the field sidebar without checking `_raw`.** The sidebar shows what Splunk thinks is in your data. When the answer matters, expand one event and verify. Common failure: an auto-KV extraction picks up `user=alice` from a log line that contains `requested_by_user=alice` — your `user` field is now polluted with `requested_by_user` values too.
4. **Running everything in Verbose.** Verbose returns every field on every event and writes a fat artifact. On a busy search head it is a credible cause of dispatch-directory pressure. If you genuinely need every field, run Verbose on a narrow time window, then drop back to Smart.
5. **Leaving the time picker on "All time" by reflex.** "All time" on a busy index is rarely what you want. Even if the data only goes back 30 days, you have just asked the search head to confirm that there is nothing older — that is work. Default to `-24h@h` or `-7d@h`.
6. **Copy-pasting SPL from blog posts without checking the version.** SPL from a 7.x blog often works in 9.x; sometimes it does not, and the failure is silent (a default changed, a field name was renamed). Note the version of any snippet you import, and prefer the official Search Reference over third-party rewrites.
7. **Treating the Job History as durable storage.** Ad-hoc jobs expire on their TTL. If a result matters for an investigation that will outlive the next coffee break, save the search or extend the TTL; do not assume "I'll click back into it later" will work.
8. **Searching from the wrong app context without realizing it.** Macros, eventtypes, tags, and lookups resolve **through the current app**. Run the same SPL from `search` versus from `my_company_app` and you can get two different result sets, because the latter sees private knowledge objects the former does not. When a search "stops working" after you switched apps in the bar, that is your first hypothesis.

## Worked examples

### Read a slow search through the Job Inspector

Assume you ran the following over the last 24 hours and it took 90 seconds:

```spl
index=os sourcetype=linux_secure
| stats count by host, user
```

You open the Job Inspector and look at three things in this order:

1. **Execution costs** — the table that ranks each phase by time. If `command.search.index` dominates, the base search is reading too many events; tighten `index`/`sourcetype`/`host` or shrink the time range. If `command.stats` dominates, you are processing too many results post-filter; consider whether `tstats` against an indexed-field or accelerated-data-model variant would work (see Chapter 4).
2. **`eventCount` vs `resultCount`** — how many events the base read versus how many rows came out. A 10× ratio between the two is normal for `stats`; a 1000× ratio means your filter is doing the heavy lifting too late.
3. **`normalizedSearch`** — what Splunk actually ran. Saved searches, macros, and eventtypes get expanded here; you may discover that a macro you reused pulls in an `index=*` you did not authorize.

You do not need to fix anything yet — you need to know which lever to pull.

### Why `_raw` is the source of truth

Two searches against the same dataset:

```spl
index=os sourcetype=linux_secure user=alice earliest=-24h@h latest=now
| stats count
```

```spl
index=os sourcetype=linux_secure earliest=-24h@h latest=now
| search _raw="*user=alice*"
| stats count
```

If the two counts disagree, you have a field-extraction problem, not a logging problem. The first search trusts the extracted `user` field; the second trusts `_raw`. Pick one event from the symmetric difference, expand `_raw`, and you will see which side is lying. Until you have done this once on a real dataset, the lesson does not stick.

### A job that disappears from Job History

You ran a search at 09:00, came back at 14:00, and it is gone from the Job History.

The artifact's TTL expired. By default, ad-hoc dispatched jobs have a TTL on the order of ten minutes; saved/scheduled jobs get a longer TTL set on the saved search. You did not lose any data — the indexes are untouched — you lost the **artifact** (the materialized result set). To keep results around, save the search or extend its TTL via the Save → "expires" knob. If your team needs longer-lived artifacts as a matter of policy, that is a role-level setting and an admin call (see escalation below).

### Fast vs Smart vs Verbose on the same search

Take the exact same SPL, run it three times by flipping the mode:

```spl
index=os sourcetype=linux_secure host=web01 earliest=-1h@h latest=now
| head 200
```

- **Fast.** You get the events, a minimal set of fields, and no event sampling. The sidebar shows the indexed fields and a handful of auto-extracted ones. Job is cheap, artifact is small.
- **Smart.** This is the default. If your search is non-transforming, Splunk runs field discovery and the sidebar fills with extracted fields. If your search ends in a transforming command, Smart silently behaves like Fast for the discovery phase.
- **Verbose.** All fields, no sampling, full segmentation. The artifact balloons. You can now click any field and pivot, at the cost of a much bigger dispatch directory.

The lesson is not "Verbose is bad"; it is "Verbose is a tool you reach for, not the default the search bar should be left in". When you finish a Verbose investigation, set the mode back.

## When to escalate to an admin

- **You suspect a sourcetype is misparsed at index-time** (event boundaries wrong, multi-line events stitched, timestamps off by hours, timezone wrong, host attributed to the forwarder instead of the source machine). The fix is in `props.conf` and `transforms.conf` on the indexing tier — admin-only. Ask for: "review of `props.conf` for sourcetype `linux_secure` on the indexing tier; symptoms: …; example event: …".
- **You need a new sourcetype, a new index, or a new field extracted at index-time.** All three sit on the indexing tier and require an onboarding ticket. Ask for: "data onboarding: new source `…`, proposed sourcetype `…`, proposed index `…`, retention `…`, expected volume `…`". Bring sample events, not screenshots.
- **A search you ran hours ago has dropped out of the Job History before you saved it.** Artifact TTL expired; the default is configurable per role. Ask for: "raise TTL of ad-hoc dispatched jobs for role `analyst` to N minutes, justification: investigation workflow requires returning to artifacts after a meeting".
- **You see "Search peer not responding" or "indexer cluster degraded" banners.** This is an ops incident, not a search problem. Stop running searches against the affected tier, notify ops with the banner text and the time, and wait. Retrying does not help and adds load.
- **Your role's search quotas are blocking ad-hoc work** (`srchJobsQuota` reached, `srchDiskQuota` exceeded, `The maximum number of concurrent…` errors). This trigger is documented end to end — including the ask template — in [Chapter 1 — search quotas](01-spl-search-anatomy.md#when-to-escalate-to-an-admin); see that chapter when the symptom comes up.

## Sources

- [Splunk Enterprise 9.4 — Distributed Search Manual — About distributed search](https://docs.splunk.com/Documentation/Splunk/9.4/DistSearch/Whatisdistributedsearch)
- [Splunk Enterprise 9.4 — Search Manual — Search modes](https://docs.splunk.com/Documentation/Splunk/9.4/Search/Changethesearchmode)
- [Splunk Enterprise 9.4 — Search Manual — View search job properties with the Job Inspector](https://docs.splunk.com/Documentation/Splunk/9.4/Search/ViewsearchjobpropertieswiththeJobInspector)
- [Splexicon](https://docs.splunk.com/Splexicon) — canonical definitions for *event*, *result*, *dispatch directory*, *artifact*, *TTL*, *knowledge object*, *app context*.
