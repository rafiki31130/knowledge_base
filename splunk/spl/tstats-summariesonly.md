# `tstats` et `summariesonly` : recherche accélérée

`tstats` interroge directement les **index tsidx** (les fichiers d'index de
Splunk) au lieu de relire les évènements bruts. Sur de gros volumes, l'écart de
performance se compte en ordres de grandeur. La contrepartie : `tstats` ne voit
que des champs **indexés** ou exposés par un **modèle de données accéléré**, et
le mot-clé `summariesonly` change ce qu'il a le droit de lire.

## Pourquoi c'est rapide

Une recherche `search` classique parcourt les évènements bruts, les décompresse,
en extrait les champs à la volée. `tstats` lit des structures pré-calculées
(`.tsidx`) : il agrège des compteurs sans toucher au texte des évènements. Moins
de données lues = recherche plus rapide.

La conséquence directe : `tstats` ne sait répondre qu'à des questions
**agrégées** (compter, sommer, lister des valeurs distinctes), pas restituer le
contenu intégral d'un évènement.

## La forme générique sur un modèle de données

```spl
| tstats count
    from datamodel=<datamodel>
    where nodename=<noeud> earliest=-24h latest=now
    by <datamodel>.<champ1>, <datamodel>.<champ2>
```

Champ par champ :

- `| tstats` — commande génératrice : elle commence la recherche (le `|`
  initial est obligatoire, comme pour `tstats` et `from`).
- `count` — la statistique calculée ; on peut chaîner `count`, `dc(<champ>)`,
  `sum(<champ>)`, `values(<champ>)`, etc.
- `from datamodel=<datamodel>` — source : un modèle de données. Les champs sont
  alors préfixés par le nom du modèle (`<datamodel>.<champ>`).
- `where ... earliest / latest` — **early filtering** : borner le temps et les
  conditions le plus tôt possible réduit le volume scanné.
- `by ...` — dimensions d'agrégation (l'équivalent du `by` de `stats`).

On peut aussi faire du `tstats` **sans modèle**, sur des champs indexés :

```spl
| tstats count where index=<index> by sourcetype, host
```

Ici seuls des champs indexés par défaut (`index`, `sourcetype`, `host`,
`source`, `_time`) sont disponibles — pas les champs extraits au search-time.

## `summariesonly` : la bascule à comprendre

Un modèle de données accéléré entretient des **résumés** (summaries) pré-calculés
pour une fenêtre de rétention donnée. `summariesonly` contrôle si `tstats` a le
droit de compléter avec les évènements bruts.

```spl
| tstats summariesonly=true count
    from datamodel=<datamodel>
    where earliest=-24h latest=now
    by <datamodel>.<champ>
```

| Valeur | Comportement | Effet |
| --- | --- | --- |
| `summariesonly=false` (défaut) | Lit les résumés **et** complète avec les évènements bruts pour la part non encore résumée | Résultats complets, mais plus lent et variable |
| `summariesonly=true` | Lit **uniquement** les résumés accélérés | Très rapide et déterministe, mais **ignore** les données pas encore résumées ou hors fenêtre d'accélération |

Le piège : avec `summariesonly=true`, les évènements **récents** (pas encore
intégrés au résumé) ou **anciens** (hors rétention d'accélération) sont
**absents** du résultat. Un comptage qui « manque » des évènements connus est
souvent un `summariesonly=true` appliqué à une fenêtre mal couverte par
l'accélération.

## Vérifier la couverture d'accélération

Avant de se fier à `summariesonly=true`, vérifier que le modèle est bien accéléré
et jusqu'où vont ses résumés :

```spl
| tstats count
    from datamodel=<datamodel>
    where earliest=-7d latest=now
    by _time span=1d
| sort _time
```

Des jours à `0` ou manquants au sein de la fenêtre théorique d'accélération
indiquent un résumé incomplet (rattrapage en cours, accélération récente,
ressources insuffisantes).

## Quand utiliser quoi

- **Tableaux de bord à rafraîchissement fréquent** sur de gros volumes :
  `tstats summariesonly=true` — rapidité et stabilité priment sur l'exhaustivité
  de la dernière minute.
- **Investigation où aucun évènement ne doit manquer** : `summariesonly=false`
  (ou repasser à une `search` brute pour le détail), quitte à être plus lent.
- **Comptages exploratoires sur champs indexés** : `tstats` sans modèle, c'est le
  moyen le plus rapide de cardinaliser par `index` / `sourcetype` / `host`.

## À retenir

- `tstats` lit l'index, pas les évènements bruts : très rapide, mais limité aux
  champs indexés ou aux modèles de données accélérés.
- Filtrer tôt (`where`, `earliest`/`latest`) : c'est là que se gagne la perf.
- `summariesonly=true` = uniquement les résumés : rapide et déterministe, mais
  **peut omettre** le récent et l'ancien hors fenêtre d'accélération.
- Un résultat « incomplet » de façon inexpliquée → suspecter `summariesonly` et
  vérifier la couverture d'accélération.

## Voir aussi

- [`_time` vs `_indextime` : ne pas les confondre](time-vs-indextime.md)
- [`stats` vs `eventstats` vs `streamstats`](stats-eventstats-streamstats.md)
- [Multivalue en SPL : `mvexpand`, `mvfilter`, `mvcount`](multivalue-spl.md)
