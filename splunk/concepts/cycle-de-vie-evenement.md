# Cycle de vie d'un évènement Splunk : input → parsing → index → search

Un évènement traverse plusieurs **phases** entre sa lecture à la source et son
affichage dans une recherche. Chaque phase a un **lieu d'exécution** (quel
composant) et un **moment** (ingestion vs recherche). Configurer un traitement
au mauvais endroit est une source de bugs récurrente : le paramètre est ignoré,
ou il s'applique trop tard pour avoir l'effet voulu.

Cette fiche donne la vue d'ensemble. Pour le détail de **ce qui s'exécute sur
un UF par rapport à un HF/indexer** pendant la parsing phase, voir
[Parsing phase : ce qui s'exécute où](parsing-phase-uf-vs-hf.md) (ne pas le
recopier ici).

## Les quatre phases

```text
   SOURCE
     │
     ▼
 ┌────────────┐   input phase      où : forwarder (UF/HF) ou indexer
 │   INPUT    │   - lecture (fichier, port, script, API)
 └─────┬──────┘   - métadonnées source/sourcetype/host posées
       │
       ▼
 ┌────────────┐   parsing phase    où : HF ou indexer (PAS un UF nu)
 │  PARSING   │   - découpage en lignes/évènements
 └─────┬──────┘   - extraction du timestamp (_time)
       │          - transforms index-time, routing, masquage
       ▼
 ┌────────────┐   index phase      où : indexer
 │   INDEX    │   - écriture sur disque (buckets), _indextime posé
 └─────┬──────┘   - construction des index tsidx
       │
       ▼
 ┌────────────┐   search phase     où : search head + indexers
 │   SEARCH   │   - extractions search-time, lookups, calculs
 └────────────┘   - aucune modification de la donnée stockée
```

### 1. Input phase — lire et étiqueter

C'est la lecture brute à la source : suivi de fichier, écoute d'un port
réseau, exécution d'un script, appel d'API. Cette phase **pose les
métadonnées** de base — `source`, `sourcetype`, `host`, `index` — qui orientent
tout le traitement aval. Elle s'exécute sur le composant qui collecte
(forwarder ou, en collecte directe, l'indexer).

```ini
# inputs.conf — étiquetage à la collecte (forme générique)
[monitor:///var/log/<application>]
sourcetype = <ma_sourcetype>
index      = <index>
```

Si le `sourcetype` est mal posé ici, tout le parsing aval applique les mauvaises
règles. C'est le premier endroit à vérifier quand un évènement « ne se parse
pas comme prévu ».

### 2. Parsing phase — découper et dater

C'est ici que la donnée brute devient des **évènements structurés** : découpage
en lignes (`LINE_BREAKER`), fusion ou non en multi-lignes (`SHOULD_LINEMERGE`),
troncature (`TRUNCATE`), et surtout **extraction du timestamp** qui alimente
`_time` (`TIME_PREFIX`, `TIME_FORMAT`, `MAX_TIMESTAMP_LOOKAHEAD`). Les
transforms **index-time** (routing vers un autre index, masquage de données,
remplacement de `host`) agissent aussi à ce moment.

Point critique : sur un Universal Forwarder nu, la parsing phase **ne s'exécute
pas** — elle est reportée sur le HF ou l'indexer. C'est pourquoi poser
`TIME_FORMAT` dans le `props.conf` d'un UF reste sans effet. Le détail exhaustif
de la répartition UF/HF est dans la fiche dédiée :
[Parsing phase : ce qui s'exécute où](parsing-phase-uf-vs-hf.md).

### 3. Index phase — écrire et horodater l'arrivée

L'indexer écrit les évènements parsés sur disque, dans des **buckets**, et
construit les index `tsidx` qui rendent la recherche rapide. C'est ici qu'est
posé `_indextime` : l'instant où l'évènement a été indexé, **distinct** de
`_time` (l'instant de l'évènement lui-même). Confondre les deux fausse les
investigations — voir
[`_time` vs `_indextime`](time-vs-indextime.md).

Une fois écrite, la donnée stockée est **immuable** : aucune phase ultérieure
ne la modifie. Tout ce qu'on veut transformer de façon permanente doit l'être
**avant** ou **pendant** l'index phase.

### 4. Search phase — interpréter à la lecture

À la recherche, Splunk applique les traitements **search-time** : extractions
de champs (`EXTRACT-*`, `KV_MODE`), lookups, `eval`, alias de champs. Ces
opérations s'exécutent sur les indexers (filtrage proche des données) et le
search head (calculs finaux), **sans toucher** à la donnée stockée. On peut donc
les corriger et rejouer une recherche sans réindexer.

```spl
index=<index> sourcetype=<ma_sourcetype>
| rex field=_raw "user=(?<user>\w+)"   # extraction search-time : rejouable
| stats count by user
```

## La règle à retenir : index-time vs search-time

| Question | Réponse |
| --- | --- |
| Je veux **router**, **masquer**, **fixer le timestamp** | index-time → parsing phase (HF/indexer), **avant** écriture |
| Je veux **extraire un champ**, faire un **lookup**, un **calcul** | search-time → rejouable, pas de réindexation |
| Mon paramètre `props.conf` est ignoré sur la source | il appartient sûrement à la parsing phase, qui ne tourne pas sur un UF nu |

Corollaire : **un traitement index-time appliqué après coup ne corrige pas les
données déjà indexées** — il ne vaut que pour les évènements à venir. Si la donnée
historique est mal parsée, soit on réindexe, soit on rattrape en search-time.

## Voir aussi

- [Parsing phase : ce qui s'exécute où](parsing-phase-uf-vs-hf.md) — détail UF vs HF/indexer
- [`_time` vs `_indextime`](time-vs-indextime.md) — les deux horodatages à ne pas confondre
- [Cycle de vie des buckets en multisite](buckets-multisite-lifecycle.md) — ce que devient la donnée après l'index phase
