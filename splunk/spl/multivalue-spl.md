# Multivalue en SPL : `mvexpand`, `mvfilter`, `mvcount`

Un champ Splunk peut contenir **plusieurs valeurs** sur un même évènement : un
champ *multivalue* (MV). C'est fréquent après un `stats values(...)`, un
`makemv`, ou quand une source liste plusieurs destinataires, plusieurs IP,
plusieurs tags dans un seul champ. Traiter un champ MV comme un champ simple
produit des résultats faux **sans erreur** : la fiche détaille les trois
commandes/fonctions clés pour les manipuler proprement.

## Reconnaître un champ multivalue

Un champ MV s'affiche sur plusieurs lignes dans une même cellule du tableau de
résultats. Pour le créer ou le visualiser de façon contrôlée :

```spl
... | eval destinataires = split(liste_brute, ",")
```

`split(<champ>, "<sep>")` transforme une chaîne `"a,b,c"` en champ MV de trois
valeurs. L'inverse est `mvjoin(<champ_mv>, "<sep>")`.

## `mvcount` : compter les valeurs

`mvcount(<champ>)` renvoie le **nombre de valeurs** d'un champ MV (ou `1` pour un
champ simple non vide, `null` si vide).

```spl
... | eval nb_dest = mvcount(destinataires)
| where nb_dest > 5
```

Cas d'usage : repérer les évènements « anormalement larges » (un message à un
grand nombre de destinataires, une requête touchant beaucoup de cibles) sans
déplier le champ.

## `mvfilter` : filtrer les valeurs d'un champ MV

`mvfilter(<expression>)` garde, **au sein** d'un champ MV, uniquement les valeurs
qui satisfont l'expression. Le résultat reste un champ MV (réduit).

```spl
... | eval ip_externes = mvfilter(!cidrmatch("10.0.0.0/8", ips))
```

Ici `ips` est un champ MV ; on ne conserve que les adresses **hors** plage
privée. Autres exemples :

```spl
# Garder les valeurs correspondant à un motif
... | eval erreurs = mvfilter(match(codes, "^5\d\d$"))

# Garder les valeurs au-dessus d'un seuil
... | eval gros = mvfilter(tailles > 1000)
```

`mvfilter` opère **valeur par valeur** sur un seul champ MV — l'expression ne
peut référencer que ce champ. Pour croiser plusieurs champs, déplier d'abord
(`mvexpand`).

## `mvexpand` : déplier en plusieurs évènements

`mvexpand <champ>` transforme **un** évènement à champ MV en **autant**
d'évènements qu'il y a de valeurs, chacun portant une seule valeur du champ. Les
autres champs sont dupliqués sur chaque ligne.

```spl
index=<index> sourcetype=<sourcetype>
| eval destinataires = split(liste_brute, ",")
| mvexpand destinataires
| stats count by destinataires
```

Avant `mvexpand`, un évènement = une ligne avec N destinataires. Après, N lignes
d'un destinataire chacune — ce qui rend possible un `stats ... by destinataires`
correct.

Pièges :

- **Explosion du volume** : un évènement à 100 valeurs devient 100 évènements.
  Filtrer (`where`, `mvfilter`) **avant** de déplier.
- **Limite mémoire** : `mvexpand` est borné par une limite de taille
  (`mv_max_results` / `max_mem_usage_mb` selon la version) ; au-delà, des
  résultats sont silencieusement tronqués. Réduire en amont.
- **Perte de corrélation** : après dépliage, chaque ligne ne « sait » plus qu'un
  évènement d'origine en groupait plusieurs. Conserver une clé (`eval id =
  ...`) si on doit recoller.

## Choisir la bonne approche

| Besoin | Outil | Garde la structure MV ? |
| --- | --- | --- |
| Compter les valeurs | `mvcount(<champ>)` | oui (champ inchangé) |
| Sous-ensemble de valeurs | `mvfilter(<expr>)` | oui (champ réduit) |
| Agréger / corréler valeur par valeur | `mvexpand` | non (un évènement par valeur) |
| Une valeur précise par position | `mvindex(<champ>, <i>)` | extrait une valeur |
| Reformer une chaîne | `mvjoin(<champ>, "<sep>")` | non (redevient simple) |

Règle générale : **rester en MV tant que possible** (compter, filtrer), ne
`mvexpand` que lorsqu'une agrégation `by` l'exige — et toujours après avoir
réduit le volume.

## À retenir

- Un champ MV porte plusieurs valeurs ; le traiter comme simple fausse les
  comptages.
- `mvcount` compte, `mvfilter` filtre en restant MV, `mvexpand` déplie en
  évènements distincts.
- `mvexpand` peut faire exploser le volume et tronquer silencieusement : filtrer
  avant.

## Voir aussi

- [`stats` vs `eventstats` vs `streamstats`](./stats-eventstats-streamstats.md)
- [`tstats` et `summariesonly` : recherche accélérée](./tstats-summariesonly.md)
- [Regex pour les logs : greedy, ancres, lookaround](../../concepts/regex-pour-logs.md)
