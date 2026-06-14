# Chapter 1 — SPL: anatomy of a good search

> Most searches that are slow, wrong, or unreadable are not slow, wrong, or unreadable because of clever syntax — they are that way because the commands are in the wrong order. A good SPL search has the same four stages every time: scope the data, filter what survives, transform what is left, present the result. Internalize that shape and you can read someone else's SPL in five seconds, write your own without backtracking, and diagnose a broken search by checking which stage went off the rails.

## Quick refresher

Keep these distinctions in working memory; the rest of the chapter leans on them.

- **Pipeline order matters.** SPL flows left to right. The base search before the first `|` is the cheapest filter you have; everything after pays for every event the base let through.
- **Streaming vs transforming.** Streaming commands (`eval`, `where`, `rex`, `fields`) run on the indexers and pass events through. Transforming commands (`stats`, `chart`, `timechart`, `top`) collapse events into a result set on the search head — after them you have rows, not events.
- **`search` vs `where`.** `search` matches keywords against `_raw` and indexed/extracted fields, with wildcards and booleans. `where` evaluates `eval`-style boolean expressions on field *values* (`like()`, `isnotnull()`, arithmetic) and only sees fields that already exist.
- **`fields` vs `table`.** `fields +foo,bar` early in the pipeline stops field discovery for fields you do not need — a real perf lever. `table` is presentation only; it picks columns and is not `dedup`.
- **`eval` vs `rex`.** `eval` computes new fields from existing ones. `rex` extracts a new field from `_raw` with a regex. Reach for `rex` only when the field is not already extracted.
- **First pipe matters.** Splunk's optimizer is less aggressive than a relational query planner. A filter that could have lived in the base search but ended up after a `| stats` paid for the full scan first.

## Major good practices

1. **Order every search the same way: scope, filter, enrich, transform, present.** Scope is `index sourcetype host source` plus the time picker. Filter is `search` or `where` against fields you already have. Enrich is `eval`, `lookup`, occasional `rex`. Transform is `stats`/`chart`/`timechart`. Present is `sort`, `rename`, `table`. When you read someone else's SPL in this order, broken searches stand out — the `| search status=500` after the `| stats` is suddenly obvious. When you write in this order, you stop discovering at the bottom of the pipe that you needed a filter at the top.
2. **Push every constant filter into the base search.** Keywords, `index=`, `sourcetype=`, `host=`, `source=`, indexed fields, and concrete literal values belong before the first `|`. Each one shrinks what the indexers ship to the search head. A `host=web01` moved from `| search host=web01` to the base search routinely turns a 30-second search into a 3-second one on a busy index, and the saving compounds across the cluster. See [Search Manual — Write better searches](https://docs.splunk.com/Documentation/Splunk/9.4/Search/Writebettersearches).
3. **Project fields early with `| fields +foo,bar` when you know your targets.** On a verbose sourcetype with dozens of auto-extracted fields, telling Splunk you only need a handful drops field-discovery work for every downstream command. Use the `+` form to keep an explicit list and the `-` form to drop a few; combining the two in the same `fields` clause is a frequent source of confusion. See [Search Reference — fields](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Fields).
4. **Pick `where` for field expressions, `search` for keyword matching.** `| where status >= 500 AND duration > 2` reads as code and uses `eval` functions. `| search error OR timeout` reads as a query against `_raw` and the indexed terms, with the usual case-insensitive keyword semantics. Mixing the two — `| search status>=500` — works in surprising ways with numeric coercion and ends up being a frequent bug. See [Search Reference — where](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Where) and [Search Reference — search](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Search).
5. **Use `eval` for case/coalesce/string ops; reach for `rex` only when the field is missing.** If `user` is already extracted, do not re-parse it with `rex` "to be safe" — you are paying regex cost on every event for no gain. If `user` is buried in `_raw` and search-time extraction has not picked it up, `rex` is the right tool, but write a single regex with named groups rather than chaining three `rex` clauses one after another.
6. **Comment shared SPL with a `comment` macro.** A search that lives in a dashboard or a saved object will be read by someone else in six months — possibly you, possibly with no memory of why the `stats` clause looks the way it does. A one-line `` `comment("why this filter exists")` `` after the relevant pipe pays itself back the first time someone asks. Free-form SPL with no commentary ages poorly.
7. **Always pin the time range explicitly.** Saved searches inherit the time picker last clicked; ad-hoc searches inherit whatever was on screen. For anything that will run more than once, hard-code `earliest=-24h@h latest=now` (or whatever window you actually need) at the bottom of the base search. The time picker is silently the most expensive control on the page; treat it as a parameter, not a default.

## Anti-patterns to ban

1. **Filtering after a transforming command.** `index=os sourcetype=linux_secure | stats count by host, user | search user=alice` reads from the indexers, ships every event in scope to the search head, runs the `stats` over all of it, and *then* throws away every row that is not Alice's. Move `user=alice` into the base search. If you cannot move it because you needed the unfiltered counts as well, you wanted a different shape — usually `eventstats` or a side computation.
2. **`* | search foo` instead of `index=… sourcetype=… foo`.** The bare `*` scans every index the role can read, then filters in memory. It is the same problem as `index=*`, just harder to spot in a code review. Whenever you see a leading `*`, rewrite the base.
3. **`| search` doing the work of `| where`, or vice versa.** `| search duration>2` sometimes does what you want and sometimes does not, depending on whether `duration` is extracted at the time `search` is parsed. `| where status="OK"` works but is confusing — `status=OK` in the base search reads more naturally. Pick the right tool for the predicate.
4. **Chained `rex` extractions.** Three `rex` clauses in a row, each peeling off one field, is regex cost paid three times on every event. Combine them into a single regex with named groups when the source line allows it. If the line does not allow it, you have a sourcetype problem and the long-term fix is an index-time extraction in `props.conf` — an admin call.
5. **`* OR foo` patterns that silently degrade.** A subtle one: `index=os ("error" OR foo)` looks scoped, but `foo` as a bare token plus the `OR` can defeat the term index and turn the search into a partial scan. Watch for boolean expressions with a generic side; either remove the generic clause or anchor it with a field name.
6. **Trusting `| table foo, bar` to deduplicate.** `table` is a presentation command; it does not dedupe. If you see one row in the Statistics tab and conclude that the underlying events were unique, you may be wrong — `table` just picked columns. Use `dedup foo, bar` (or, better, `stats count by foo, bar`) when uniqueness matters.
7. **Re-extracting fields the field sidebar already shows.** If `user`, `src`, and `status` are in the sidebar with reasonable values, do not write `rex` for them. If they are not, do not write `rex` for them at the top of every search forever — push the extraction up to the app's `props.conf` (admin) so everyone benefits.

## Worked examples

### Find failed SSH logins on Linux hosts in the last 24 hours

```spl
index=os sourcetype=linux_secure earliest=-24h@h latest=now
    "Failed password" host=web01
| stats count by host, user, src_ip
| sort - count
```

Read it in the canonical order: scope is `index=os sourcetype=linux_secure host=web01` plus the time picker; filter is the literal `"Failed password"` keyword (which hits the term index, so it is essentially free); transform is `stats count by host, user, src_ip`; present is `sort - count`. The keyword went into the base search rather than after a pipe — that is the move. Compare with the wrong version:

```spl
index=os sourcetype=linux_secure earliest=-24h@h latest=now
| stats count by host, user, src_ip
| search count > 0 host=web01 "Failed password"
```

Same result, ten times the work: the `stats` ran over every Linux secure event in the time range before the search head learned that you only cared about one host and one keyword.

### Top 10 source IPs by request count on a web sourcetype

```spl
index=network sourcetype=access_combined earliest=-1h@h latest=now
    status>=400
| fields +clientip, status, uri_path
| stats count by clientip
| sort - count
| head 10
```

Three things to notice. First, `status>=400` is in the base search — `access_combined` exposes `status` as a fast key, so the optimizer will use the indexed term where it can. Second, `fields +clientip, status, uri_path` is placed before `stats` so field discovery stops looking for the dozens of other extracted fields that come with `access_combined`. Third, `head 10` after the `sort` is the correct order; `head 10` before `sort` would return ten arbitrary rows and then sort those ten.

### Find a known UUID in raw logs across a wide window

```spl
index=main earliest=-7d@h latest=now
    "e3b0c442-98fc-1c14-9afb-f4ec3a5b6c7d"
| head 1
| fields _time, host, source, _raw
```

The hunt for a specific token in a wide time window is a base-search-only job. Putting the UUID literal in the base search hits the term index directly, so the indexers can short-circuit non-matching segments. `head 1` stops the pipeline at the first match — useful when you only need to confirm the token exists somewhere. Resist the urge to add `| stats values(host) by source` or similar transforming command "to see all matches": a transforming command will force the cluster to keep reading after the first hit.

### Rewrite a slow correlation as a base-search filter

A search that came in slow:

```spl
index=network sourcetype=access_combined earliest=-1h@h latest=now
| stats count by clientip
| where count > 100
| search clientip="10.0.0.0/24"
```

The intent is "noisy clients in the internal subnet". The `| search clientip="10.0.0.0/24"` at the end is the giveaway: the constraint is constant, it belongs in the base. The cleaned-up version:

```spl
index=network sourcetype=access_combined earliest=-1h@h latest=now
    clientip="10.0.0.0/24"
| stats count by clientip
| where count > 100
| sort - count
```

The Job Inspector will show `command.search.index` shrinking and `command.stats` running on a smaller result set. Same answer, lower cost.

## When to escalate to an admin

- **A field you expect to exist (e.g. `user`, `src`, `status`) is empty across all events for a sourcetype.** Search-time extraction is broken, or the field is supposed to be extracted at index-time and is not. Either way, the fix lives in `props.conf` / `transforms.conf` on the indexing tier or in the app's `local/props.conf` for search-time. Ask for: "review of field extraction for sourcetype `linux_secure`, field `user`; symptom: 0 events with the field populated over the last 24h; example event `_raw`: …".
- **Your search consistently hits role-level result limits** (`The maximum number of search results has been reached`, `maxResultsPerJob`, `srchJobsQuota`, `srchDiskQuota`). Limits live in `limits.conf` and `authorize.conf` per role. Before asking for a raise, check whether a `tstats` (Chapter 4) or a `stats by` rewrite would bring you under the limit — admins will ask. Ask for: "raise `maxResultsPerJob` for role `analyst` to N, justification: investigation pattern requires N results; Job Inspector link: …".
- **You want a permanent field alias or calculated field across the org.** A one-off `| eval src=ip` is fine in your own searches; baking `src=ip` into the data so every dashboard sees it is a configuration change in the owning app's `local/props.conf`. Ask for: "publish field alias `ip` → `src` in app `Splunk_TA_<sourcetype>`, scope: search-time, applies to sourcetype `cisco:asa`".
- **A field you need would be cheap as an indexed extraction but is currently only search-time.** This is the prerequisite for a fast `tstats` path (Chapter 4) — indexed fields are extracted at parsing time and queryable without `_raw`. The decision is admin-only because index-time extractions touch the indexing tier. Ask for: "add `src_ip` to index-time extraction for sourcetype `cisco:asa`, justification: enable `tstats` for hourly source-IP top-N, expected volume increase: …".
- **A regex you need lands in shared SPL that everyone copy-pastes.** That is a signal the extraction should be published once, not re-evaluated per search. Ask for: "publish `rex` extraction `<expression>` for sourcetype `<X>` in app `<Y>`, search-time, field name `<f>`".

## Sources

- [Splunk Enterprise 9.4 — Search Manual — Start searching](https://docs.splunk.com/Documentation/Splunk/9.4/Search/Aboutthesearchapp)
- [Splunk Enterprise 9.4 — Search Manual — Write better searches](https://docs.splunk.com/Documentation/Splunk/9.4/Search/Writebettersearches)
- [Splunk Enterprise 9.4 — Search Reference — search command](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Search)
- [Splunk Enterprise 9.4 — Search Reference — where command](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Where)
- [Splunk Enterprise 9.4 — Search Reference — fields command](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Fields)
- [Splunk Enterprise 9.4 — Search Reference — rex command](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Rex)
- [Splexicon](https://docs.splunk.com/Splexicon) — canonical definitions for *streaming command*, *transforming command*, *search pipeline*, *indexed field*.
