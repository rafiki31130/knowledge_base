# Détecter les buckets sous RF/SF

Trois approches pour identifier les buckets en dessous du `replication_factor`
ou `search_factor` cible. Chacune avec son compromis charge / précision.

## Cas d'usage

Sur un cluster d'indexeurs, savoir lesquels parmi les buckets sont :

- en dessous du nombre de copies attendu (`rep_total <= 1`),
- en dessous du nombre de copies searchables attendu (`srch_total <= 1`).

Sert au diagnostic post-incident, au suivi d'un fixup long, ou à la détection
préventive.

## Approche 1 — REST sur le Cluster Manager

```spl
| rest /services/cluster/manager/buckets splunk_server=local
| search frozen=0 standalone=0
| eval rep_total=0, srch_total=0
| foreach rep_count_by_site.*    [ eval rep_total=rep_total+'<<FIELD>>' ]
| foreach search_count_by_site.* [ eval srch_total=srch_total+'<<FIELD>>' ]
| where rep_total<=1 OR srch_total<=1
| rex field=title "^(?<index_name>[^~]+)~"
| table title index_name rep_total srch_total
        rep_count_by_site.* search_count_by_site.* origin_site
| sort srch_total rep_total
```

**Avertissement** : ce endpoint retourne **tous les buckets d'un coup**. Sur
les grands clusters (plusieurs centaines d'indexers, plusieurs centaines de
milliers de buckets), il a déjà été observé à OOM-killer des search heads.
Vérifier après incident :

```bash
dmesg | grep -i "killed process.*splunkd"
```

Mitigation possible dans `limits.conf` du CM :

```ini
[restapi]
max_rest_handler_responses_size_mb = 0
```

## Approche 2 — `dbinspect` (recommandée sur grands clusters)

Ne sollicite pas le CM. Scale linéairement avec le nombre d'indexers.

```spl
| dbinspect index=*
| stats dc(splunk_server) AS copies,
        values(splunk_server) AS peers,
        values(state)        AS states
        BY bucketId
| where copies<=1
| sort copies
```

**Limite** : `dbinspect` ne distingue pas nativement searchable /
non-searchable. Le préfixe du nom de répertoire le fait :

- `db_…` ⇒ searchable.
- `rb_…` ⇒ rawdata-only.

Reconstructible via le champ `path`.

## Approche 3 — REST peer-side distribué

```spl
| rest /services/cluster/peer/buckets splunk_server_group=indexers
| stats count                AS copies,
        values(splunk_server) AS peers,
        values(search_state)  AS states
        BY bucket_id
| eval searchable_count=mvcount(mvfilter(match(states, "Searchable")))
| where copies<=1 OR searchable_count<=1
```

Distribue la charge sur les peers au lieu de tout faire reposer sur le CM. À
privilégier sur les clusters de taille significative.

## Choix selon la taille du cluster

| Taille du cluster | Approche conseillée |
|---|---|
| Petit (quelques dizaines de peers) | REST CM (1) — simple, suffisant. |
| Moyen / grand | `dbinspect` (2) ou REST peer-side (3). |
| Très grand (centaines de peers, ≥10⁵ buckets) | `dbinspect` en premier ; éviter REST CM sans la mitigation `limits.conf`. |

## À lire à côté

- [Cycle de vie des buckets en multisite](buckets-multisite-lifecycle.md)
  — pourquoi on se retrouve avec des buckets dégradés.
- [Rebalance multisite](rebalance-multisite.md) — pour corriger
  une distribution déséquilibrée avant qu'elle ne dégénère.
