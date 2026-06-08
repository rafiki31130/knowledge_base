# SPL — Search Processing Language

Référence et patterns pour écrire des recherches Splunk.

Cibles typiques :

- Commandes de base : `search`, `where`, `eval`, `stats`, `tstats`,
  `streamstats`, `eventstats`, `transaction`, `dedup`, `rex`, `lookup`,
  `inputlookup` / `outputlookup`.
- Fonctions de `eval` / `stats`, conversions de temps, manipulations de chaînes.
- Modèles de données, accélérations, `datamodel` vs `tstats`.
- Sous-recherches, `join`, `append`, `union` : quand et pourquoi (ou pas).
- Performance : early filtering, `tstats summariesonly`, ordre des commandes.
- Pièges fréquents : multivalues, `_time` vs `_indextime`, timezones,
  `index=*`, etc.

Format d'une fiche : but → forme générique → explication champ par champ →
variantes → pièges.

## Fiches existantes

- [`_time` vs `_indextime` : ne pas les confondre](./time-vs-indextime.md)
- [`stats` vs `eventstats` vs `streamstats`](./stats-eventstats-streamstats.md)
- [`tstats` et `summariesonly` : recherche accélérée](./tstats-summariesonly.md)
- [Multivalue en SPL : `mvexpand`, `mvfilter`, `mvcount`](./multivalue-spl.md)
