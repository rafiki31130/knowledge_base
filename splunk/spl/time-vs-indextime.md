# `_time` vs `_indextime` : ne pas les confondre

Deux horodatages coexistent sur chaque évènement Splunk. Les confondre fausse
les fenêtres de recherche et les investigations. La règle tient en une phrase :
**le sélecteur de temps (la fenêtre de recherche) porte sur `_time`, jamais sur
`_indextime`.**

## Les deux champs

| Champ | Sens | Posé quand | Source |
| --- | --- | --- | --- |
| `_time` | Horodatage **de l'évènement** | À l'extraction du timestamp (parsing phase) | Le contenu de l'évènement (ligne de log) |
| `_indextime` | Horodatage **d'indexation** | Quand l'évènement est écrit dans l'index | L'horloge de l'indexer |

`_time` répond à « quand l'évènement s'est-il produit ? ».
`_indextime` répond à « quand Splunk a-t-il reçu et indexé l'évènement ? ».

> Le timestamp `_time` est posé par le HF ou l'indexer pendant la parsing
> phase, pas par le UF. Voir [Parsing phase : UF vs HF/indexer](parsing-phase-uf-vs-hf.md).

## Pourquoi l'écart existe

En régime nominal, `_indextime` suit `_time` de quelques secondes. L'écart se
creuse quand :

- la collecte est en retard (forwarder en file d'attente, lien saturé) ;
- une source rejoue d'anciens fichiers (réindexation, rattrapage) ;
- le fuseau ou le format de timestamp est mal interprété → `_time` faux ;
- l'horloge de la source dérive (voir le concept de drift d'horloge).

## La forme générique

`_indextime` n'est pas exposé tel quel : il faut le matérialiser dans un champ.

```spl
index=<index> sourcetype=<sourcetype>
| eval indextime = _indextime
| eval delai_ingestion = _indextime - _time
| table _time indextime delai_ingestion host
```

Champ par champ :

- `_time` — horodatage de l'évènement (déjà présent, pilote le sélecteur de temps).
- `_indextime` — épuré en epoch ; on l'aliase via `eval` pour pouvoir l'afficher
  ou le formater (`strftime`).
- `delai_ingestion` — l'écart, en secondes, entre indexation et évènement. Un
  délai positif élevé signale un retard d'ingestion.

## Le piège classique : la fenêtre de recherche

Le sélecteur de temps filtre sur `_time`. Un évènement **arrivé** aujourd'hui
mais **daté** d'hier (timestamp mal parsé, ou rejeu) n'apparaîtra **pas** dans
une recherche « dernières 15 minutes » : son `_time` est hors fenêtre, même si
son `_indextime` est récent.

Pour rechercher par date d'**arrivée** (ex. « qu'a-t-on indexé ces 5 dernières
minutes, quelle que soit la date des évènements ? »), filtrer explicitement sur
`_indextime` :

```spl
index=<index>
    _index_earliest=-5m _index_latest=now
| eval delai_ingestion = _indextime - _time
| stats count avg(delai_ingestion) as delai_moyen by sourcetype
```

`_index_earliest` / `_index_latest` bornent sur `_indextime` (en plus du
sélecteur de temps, qui borne toujours sur `_time`). C'est la seule façon
fiable de raisonner « par date d'indexation ».

## Cas d'usage : détecter un retard d'ingestion

```spl
index=<index> sourcetype=<sourcetype>
| eval delai_ingestion = _indextime - _time
| where delai_ingestion > 300
| stats count, max(delai_ingestion) as pire_delai by host
```

Un `delai_ingestion` durablement élevé sur un `host=indexer-01` ou une source
donnée indique un goulot de collecte, pas une anomalie applicative.

## À retenir

- Le sélecteur de temps = `_time`. Toujours.
- Pour raisonner par arrivée des données : `_index_earliest` / `_index_latest`.
- Un `_time` faux (fuseau, format) rend des évènements « invisibles » dans la
  fenêtre attendue : vérifier `delai_ingestion` quand des données « manquent ».

## Voir aussi

- [`stats` vs `eventstats` vs `streamstats`](stats-eventstats-streamstats.md)
- [Parsing phase : UF vs HF/indexer](parsing-phase-uf-vs-hf.md)
