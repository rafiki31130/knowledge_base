# Chapter 2 — SPL: `stats`, transforming commands and the `| stats` mindset

> You already know `| stats count by user`. You also still reach for `top`, `chart`, `transaction`, or a sneaky `eventstats` when a search gets uncomfortable — and you pay for it later in correctness, performance, or both. This chapter pins down what makes a command *transforming* versus *streaming*, why `stats` should be your default tool, and which of `eventstats`, `streamstats`, `chart`, `timechart` and `transaction` you actually need. After it you should write fewer searches, read other people's searches faster, and stop fighting `streamstats` for windowed counts.

## Quick refresher

Keep these distinctions on hand before the rest of the chapter clicks.

- **Streaming vs transforming.** A **streaming** command processes one event at a time and runs in parallel on the indexers (`eval`, `where`, `rex`, `fields`). A **transforming** command consumes results to produce a different shape — counts, aggregates, time buckets — and runs on the search head once the streaming legs converge (`stats`, `chart`, `timechart`, `top`, `rare`). The boundary is the moment "events" become "results". See [Search Manual — About transforming commands](https://docs.splunk.com/Documentation/Splunk/9.4/Search/Abouttransformingcommands).
- **`stats` / `chart` / `timechart`.** All transforming. `stats` is the general form. `chart` is `stats` laid out as a 2-D crosstab. `timechart` is `chart` with `_time` on the X axis and an implicit `bin _time`.
- **`top` / `rare`.** Wrappers around `stats count` + `sort` + `head` with surprise defaults (`limit=10`, `useother=t`).
- **`eventstats` / `streamstats`.** Non-transforming aggregators. `eventstats` writes a dataset-wide aggregate back onto every row without collapsing. `streamstats` computes a running aggregate row by row, optionally inside a window. Both stay in the result pipeline — that is why you reach for them when `stats` would lose row context.
- **`by` and cardinality.** Every `by` value expands the grid. `by host, user, action, sourcetype` over an hour of `linux_secure` is a cardinality blast that fills the dispatch directory and may truncate against `maxResultRows`.
- **Defaults that bite.** `top` truncates at `limit=10`. `timechart` rolls past `limit` into `OTHER` and keeps `NULL`. `stats values()` is the opposite hazard: the per-cell `maxvalues` ships unbounded by default, so a `values(*)` over a busy field can balloon to tens of thousands of elements per row before any role-level cap (`maxresultrows`, typically 50 000) kicks in downstream.

## Major good practices

1. **Default to `stats` over `top` and `rare`.** `| stats count by user | sort - count | head 10` is one command longer than `| top 10 user`, and it gives you a result you can compose, accelerate, and review. The `top`/`rare` shorthand looks tidy on a Slack screenshot and then bites you the next time you need to add a second aggregator, exclude nulls, or feed the output into a `lookup`. Treat `top` and `rare` as ad-hoc UI gestures, not as artifacts you save.
2. **Reach for `eventstats` only when you need a per-row enrichment that depends on the dataset.** "Share of total" is the canonical case: you need `total = sum(count) over the whole dataset` written back onto every row to compute a percentage. If two `eventstats` start stacking, ask yourself whether `stats` then `eval` would compute the same numbers with one fewer pass.
3. **Use `streamstats` for windowed running totals and session detection — and always bound the window.** `streamstats` is the right tool for "rolling 5-minute count per user" and "label every login that follows a logout from the same user". It is also the easiest way to OOM a search head: an unbounded `streamstats sum(...)` keeps state for every distinct `by` group across every event. Always pair it with `window=` (rows), `time_window=` (seconds), or a `reset_on_change=t` upstream.
4. **Use `timechart` only when you need a time bucket on the X axis.** It bundles `bin _time` and a layout decision in one command, which is convenient and lossy. If you need the time bucket but a non-standard layout — say, an aggregate per bucket *and* a percentile per bucket, then a comparison across two `by` fields — you will spend less time writing `| bin _time span=5m | stats … by _time, …` than fighting `timechart`'s defaults.
5. **Push exactly the `by` fields you need, and inspect the cardinality before committing.** A quick `| stats dc(field) as cardinality_field` on the same time window tells you whether `by field` is going to return 200 rows or 200 000. Saved searches, alerts, and accelerations live with the cardinality you pushed; a 200 000-row scheduled search is a quiet way to keep the indexers busy.
6. **Know what `timechart` defaults hide.** `useother=t` rolls every series past `limit` into `OTHER`; `usenull=t` keeps the `NULL` series. When someone asks "where did host `web03` go in the chart?", the answer is often "into `OTHER`, because `limit=10`". Flip them off explicitly when the visual question is "where exactly is *this* series?". See [Search Reference — timechart](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Timechart).
7. **Reach for `transaction` only when you genuinely need ordered, bounded sequences of events.** `transaction startswith=… endswith=… maxspan=…` walks the event stream to build groups — exactly what you want when order and gaps inside the group matter. For "earliest and latest event per host" or "count distinct sessions per user", `stats by` with `earliest()`/`latest()` is dramatically faster and easier to accelerate. See [Search Reference — transaction](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Transaction).

## Anti-patterns to ban

1. **`top user` followed five seconds later by `| stats count by user`.** You ran the aggregation twice. The second one usually exists because `top` did not give you the column you actually wanted (a second aggregator, a non-default sort, a filter). Save the first pass as `stats` and skip the second.
2. **Using `transaction` to do what `stats` can do — 10× slower.** `transaction startswith=… endswith=…` is justifiable for genuine event sequencing. `transaction user` to group a user's events into "sessions" is almost always rewriteable as `bin _time span=30m | stats … by user, _time` or as `streamstats` with a `time_window=` reset. The right pattern depends on whether you need order inside the group; if you do not, `stats` wins.
3. **`stats values(*)` on an unbounded dataset.** `values(*)` builds a deduplicated list per result row across every field. On `linux_secure` over a day, this is a memory hazard. Either restrict to the fields you want (`values(user) values(action)`) or precede it with a `head` / `dedup` / `stats by`. If the goal is "show me the fields present", run `| fieldsummary` instead.
4. **`eventstats` then `where` to filter out the bottom of a distribution.** When the intent is "keep only users above some threshold", `eventstats sum(count) as total | eval pct = count/total | where pct > 0.05` walks every row twice. The simpler form is `stats count by user | sort - count | head N`, or `stats count by user | where count > X`. Save `eventstats` for cases where the post-filter result legitimately depends on a global aggregate.
5. **Three `timechart` in a single search "to compare".** `timechart` is transforming; chaining three of them means three full passes over the data, with an `append` or `appendcols` between them that re-bins the time series. Either split into three independent panels (dashboards) or use a single `| bin _time span=…` followed by `stats … by _time, dimension`.
6. **`stats list(...)` to "see all values" without an upstream cap.** `list()` keeps every value, in order, with duplicates. On an unbounded `by`, the artifact balloons and the `list()` columns get truncated silently at the per-row limit. If you only want a sample, `| head N` upstream and `list()` downstream. If you want the distinct set, use `values()`. If you want the count, you wanted `stats count` all along.
7. **`top` inside a saved search whose downstream consumer needs structured output.** `top` synthesizes a `percent` column and a `count` column with names you do not always remember. When a saved search feeds a dashboard panel or a lookup, the implicit schema is fragile. `| stats count as <name> by <field> | eventstats sum(count) as total | eval percent = round(100 * count / total, 2)` is verbose and explicit — and the next maintainer will not have to read the docs to understand the columns.
8. **Unbounded `streamstats` for "rolling N-minute" counts.** `streamstats sum(count) as rolling by user time_window=5m` is correct. `streamstats sum(count) as rolling by user` is a foot-cannon — it accumulates from the beginning of the dataset, per user, and the artifact grows with cardinality. The forgotten window is the single most common cause of "my search head ran out of memory" on a self-served alert.

## Worked examples

### Sessionize web logs with `streamstats` (bounded)

You want to label every web request with a session id, where a session is "requests by the same `clientip` separated by at most 30 minutes of inactivity". `transaction` is the textbook reach; `streamstats` is faster and bounds memory if you do it correctly.

```spl
index=main sourcetype=access_combined earliest=-24h@h latest=now
| sort 0 clientip _time
| streamstats current=f last(_time) as prev_time by clientip
| eval gap = _time - prev_time
| eval new_session = if(isnull(gap) OR gap > 1800, 1, 0)
| streamstats sum(new_session) as session_id by clientip
| stats min(_time) as session_start max(_time) as session_end count as hits
        by clientip, session_id
```

What to notice. The first `streamstats` looks back at the previous event *for the same `clientip`*; the `by clientip` keeps state per group, which is precisely what makes it OOM-prone if you forget to bound it. Here the bound is the time range (`earliest=-24h@h`) plus the `sort 0 clientip _time` that lets each group flush as we move on. `current=f` ensures the previous row is *strictly* previous. If you instead wrote `streamstats sum(new_session) as session_id` (no `by clientip`), the session counter would advance globally and you would mix sessions across clients without noticing.

Compare with the wrong version:

```spl
index=main sourcetype=access_combined earliest=-24h@h latest=now
| transaction clientip maxpause=30m
| eval hits = mvcount(_raw)
```

`transaction` works on small windows and small cardinality. Over a busy `access_combined` over 24 hours, expect minutes of search-head CPU, a fat artifact, and a real risk of triggering `maxevents` truncation; the resulting "transactions" near the truncation boundary are silently incomplete.

### Compute a "share of total" with `eventstats`

You need each user's request count and their share of the global request count.

```spl
index=network sourcetype=cisco:asa earliest=-24h@h latest=now
| stats count by user
| eventstats sum(count) as total
| eval pct = round(100 * count / total, 2)
| sort - count
```

What to notice. The `stats` collapses to one row per user; the `eventstats sum(count) as total` writes the global total back onto every row, *without* collapsing further. This is the one pattern that justifies `eventstats` over `stats`: the per-row enrichment depends on the dataset. Trying to do it in a single `stats` does not work because `stats` cannot reference its own aggregate.

The anti-pattern would be:

```spl
…
| eventstats sum(count) as total
| eventstats sum(if(count > total/100, 1, 0)) as users_above_1pct
```

Two `eventstats` in a row when the second can be a `stats` over the already-collapsed result. Rewrite the second with `| eval flag = if(count > total/100, 1, 0) | stats sum(flag) as users_above_1pct` or with `where pct > 1 | stats count as users_above_1pct`.

### Migrate a `transaction` to `stats earliest() latest()`

You inherited a saved search that builds "user sessions" and computes their duration:

```spl
index=os sourcetype=linux_secure earliest=-7d@d latest=now action IN (success, failure)
| transaction user startswith=eval(action="success") endswith=eval(action="failure") maxspan=1h
| eval duration = duration
| stats avg(duration) p95(duration) by user
```

The intent — "between each `success` and the next `failure` for a given user, measure the gap" — can be expressed with `stats` and ordered timestamps:

```spl
index=os sourcetype=linux_secure earliest=-7d@d latest=now action IN (success, failure)
| sort 0 user _time
| streamstats latest(eval(if(action="success", _time, null()))) as last_success by user
| where action="failure" AND isnotnull(last_success)
| eval duration = _time - last_success
| stats avg(duration) p95(duration) by user
```

What to notice. The rewrite stays in streaming/`stats` territory and never builds a `transaction` artifact. It is composable: the next maintainer can swap the percentile, add a `by host`, or window the search without rediscovering `transaction`'s knobs. The Search Reference is explicit that `transaction` is expensive and should be the fallback rather than the default ([Search Reference — transaction](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Transaction)).

### `timechart` vs `bin _time | stats` for a non-trivial layout

You want a 5-minute time series of failed SSH counts *and* the per-bucket distinct count of source IPs, broken down by `host`.

```spl
index=os sourcetype=linux_secure action=failure earliest=-24h@h latest=now
| bin _time span=5m
| stats count, dc(src_ip) as distinct_src by _time, host
```

What to notice. `timechart count dc(src_ip) by host` works for the count, but the `dc(src_ip)` second series collides with the `by host` split (which series goes on which axis?) and the chart layout fights you. `bin _time` + `stats` gives you a flat, sortable, joinable table that any visualization can render — and it is the same data your `tstats` rewrite (Chapter 4) will produce, which makes the eventual acceleration straightforward.

## When to escalate to an admin

- **A `stats by` returns fewer rows than you expect, and you have ruled out an SPL filter mistake** → role-level `maxResultRows` / `maxOutputRows` truncated the table silently. The cap lives in `limits.conf` per role. Ask for: "review `maxResultRows` for role `analyst`; symptom: `| stats count by user, host` returns N rows where `| stats dc(user) dc(host)` shows ≫ N combinations; time range: `earliest=-24h@h`; use case: …". Bring a Job Inspector link.
- **A `transaction` you genuinely cannot avoid keeps OOM-ing or hits `maxevents`** → search-head memory sizing or per-transaction caps are admin territory. Ask for: "review SH memory headroom and `transaction` `maxevents`/`maxopentxn` for use case `<name>`; we have ruled out `stats`/`streamstats` rewrites because <reason>". Do not ask for the bump until you have ruled out the rewrite — most `transaction` searches are rewrites in disguise.
- **A `tstats` rewrite would solve your perf problem but you do not have an accelerated data model** → cross-reference to Chapter 4. The escalation path lives there (data model acceleration is admin-managed). Ask Chapter 4's question, not Chapter 2's; this trigger is here as a pointer because the symptom shows up while writing `stats`.
- **`streamstats` blows the search-head memory even with a bounded window** → you have hit either a real cardinality issue or a per-job memory cap (`max_mem_usage_mb` in `limits.conf`). Ask for: "review `max_mem_usage_mb` for role `analyst`; symptom: `streamstats … time_window=5m by host, user` exits with a memory error; cardinality of `(host, user)` over the window: …". Lead with the cardinality number — `dc()` it before you escalate.
- **You need a saved search whose output is consumed by another team's dashboard, and your `stats` schema keeps changing across edits** → that is a knowledge-object discipline problem, not a perf one, and it belongs in Chapter 7's escalation pattern (KO ownership / app context). Mentioned here because it is the most common reason a beautifully tuned `stats` ends up rewritten by someone else.

## Sources

- [Splunk Enterprise 9.4 — Search Manual — About transforming commands and searches](https://docs.splunk.com/Documentation/Splunk/9.4/Search/Abouttransformingcommands)
- [Splunk Enterprise 9.4 — Search Reference — stats](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Stats)
- [Splunk Enterprise 9.4 — Search Reference — eventstats](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Eventstats)
- [Splunk Enterprise 9.4 — Search Reference — streamstats](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Streamstats)
- [Splunk Enterprise 9.4 — Search Reference — timechart](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Timechart)
- [Splunk Enterprise 9.4 — Search Reference — transaction](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Transaction)
- [Splunk Enterprise 9.4 — Search Reference — top](https://docs.splunk.com/Documentation/Splunk/9.4/SearchReference/Top)
- [Splexicon](https://docs.splunk.com/Splexicon) — canonical definitions for *streaming command*, *transforming command*, *result*.
