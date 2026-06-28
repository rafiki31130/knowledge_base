# `stats` vs `eventstats` vs `streamstats` : trois portées d'agrégation

Les trois commandes calculent les mêmes fonctions (`count`, `sum`, `avg`,
`max`, `values`…), mais avec une **portée** différente. Choisir la mauvaise
donne soit un résultat faux, soit une perte des évènements de détail.

| Commande | Ce qu'elle produit | Garde les évènements ? | Sens du calcul |
| --- | --- | --- | --- |
| `stats` | **Réduit** : un tableau de synthèse | Non | Agrégat global par groupe |
| `eventstats` | **Enrichit** : ajoute une colonne d'agrégat | Oui | Agrégat global réinjecté sur chaque ligne |
| `streamstats` | **Cumule** : agrégat courant ligne par ligne | Oui | Agrégat partiel, dans l'ordre des évènements |

Règle mnémotechnique : **réduire** (`stats`), **enrichir** (`eventstats`),
**cumuler** (`streamstats`).

## `stats` — réduire

Transforme N évènements en un tableau de synthèse. Les évènements de détail
disparaissent ; il ne reste que les groupes et leurs agrégats.

```spl
index=<index> sourcetype=<sourcetype>
| stats count, avg(duree) as duree_moyenne by host
```

Résultat : une ligne par `host`, plus aucun évènement individuel. À utiliser
quand on veut le **résumé** et rien d'autre.

## `eventstats` — enrichir

Calcule le même agrégat que `stats`, mais le **réinjecte** sur chaque évènement
d'origine. Aucun évènement n'est perdu ; on gagne une colonne. Idéal pour
comparer chaque ligne à son groupe.

```spl
index=<index> sourcetype=<sourcetype>
| eventstats avg(duree) as duree_moyenne by host
| where duree > duree_moyenne
```

Ici on garde les évènements dont la `duree` dépasse la moyenne **de leur
propre `host`**. Impossible avec `stats` (qui aurait détruit le détail).

## `streamstats` — cumuler

Calcule un agrégat **glissant**, dans l'ordre de traitement des évènements. La
valeur sur une ligne ne tient compte que des lignes **déjà vues**. Sensible à
l'ordre : presque toujours précédé d'un `sort`.

```spl
index=<index> sourcetype=<sourcetype>
| sort 0 _time
| streamstats count as occurrence, sum(octets) as octets_cumules by user
```

Pour chaque `user`, `occurrence` est le rang de l'évènement et `octets_cumules`
la somme depuis le début. Sert aux totaux courants, aux numéros de séquence,
aux détections de seuil franchi (« la Nᵉ tentative »).

### Fenêtre glissante

`streamstats window=<n>` limite le calcul aux `n` derniers évènements — utile
pour des moyennes mobiles ou des détections de rafale :

```spl
... | sort 0 _time
| streamstats window=10 avg(latence) as latence_mobile by host
```

## Calculer un écart entre lignes consécutives

`streamstats` sert aussi à comparer une ligne à la précédente (le `current=f`
exclut la ligne courante du calcul) :

```spl
index=<index> sourcetype=<sourcetype>
| sort 0 _time
| streamstats current=f last(_time) as t_precedent by user
| eval ecart_secondes = _time - t_precedent
```

`ecart_secondes` donne le délai depuis l'évènement précédent du même `user` —
base d'une détection d'inactivité ou de rafale.

## Comment choisir

- Je veux **seulement** un résumé → `stats`.
- Je veux comparer chaque évènement à un agrégat de son groupe → `eventstats`.
- Je veux un cumul / une séquence / une fenêtre dans l'ordre du temps →
  `streamstats` (avec `sort`).

## Pièges fréquents

- **`streamstats` sans `sort`** : le « cumul » suit l'ordre d'arrivée du
  pipeline, pas le temps. Toujours trier avant.
- **`eventstats` sur de très gros volumes** : il mémorise les agrégats par
  groupe en RAM ; un `by` à très forte cardinalité coûte cher.
- **Confondre `stats` et `eventstats`** : si une recherche « perd » ses
  évènements de détail après l'agrégat, c'est qu'on a réduit (`stats`) là où il
  fallait enrichir (`eventstats`).

## Voir aussi

- [`_time` vs `_indextime` : ne pas les confondre](time-vs-indextime.md)
