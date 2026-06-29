# Regex pour les logs : greedy, ancres, lookaround

Les expressions régulières servent partout en analyse de logs : extraction de
champs, filtrage, normalisation. Quelques erreurs reviennent en boucle et
produisent des extractions fausses **sans lever d'erreur** — le plus dangereux.
Cette fiche liste les pièges classiques et la bonne pratique pour chacun.

Tous les exemples utilisent des données fictives (`user01`, `example.com`,
`10.0.0.0/24`).

## Greedy vs lazy : le piège n°1

Par défaut, les quantificateurs (`*`, `+`, `?`, `{n,m}`) sont **gourmands
(greedy)** : ils consomment le **plus** de caractères possible. Sur une ligne
contenant plusieurs occurrences du délimiteur, ils « débordent ».

```text
# Ligne d'exemple
user="user01" host="srv-01" action="login"
```

```regex
# GREEDY — faux : capture jusqu'au DERNIER guillemet de la ligne
user="(.*)"
# → capture : user01" host="srv-01" action="login

# LAZY — correct : capture jusqu'au PREMIER guillemet fermant
user="(.*?)"
# → capture : user01

# MIEUX — classe négative : plus rapide, plus claire, pas de backtracking
user="([^"]*)"
# → capture : user01
```

Règle : pour extraire « entre deux délimiteurs », préférer une **classe de
caractères négative** (`[^"]*`) au lazy (`.*?`). C'est plus lisible et bien plus
performant.

## Ancres : `^`, `$`, `\b`

Sans ancre, une regex peut matcher au milieu d'un mot.

```regex
# Sans ancre — matche aussi "preuser01", "user010", etc.
user01

# Limites de mot — matche "user01" isolé
\buser01\b

# Ancres de ligne — la ligne ENTIÈRE doit correspondre
^user01$
```

Pièges :

- **`^` et `$` en mode multiligne** : selon le moteur/flag, `$` matche la fin de
  **chaque ligne** ou la fin de **tout le texte**. Sur des évènements
  multilignes, vérifier le flag `m` (MULTILINE).
- **`\b` et les caractères non-mot** : `\b` se place entre un caractère « mot »
  (`[A-Za-z0-9_]`) et un autre. Autour d'un `-` ou d'un `.`, le comportement
  surprend (ex. dans `srv-01`).

## Lookaround : assertions sans consommation

Le lookahead/lookbehind teste une condition **sans** inclure le texte dans la
capture. Utile pour extraire une valeur qui suit ou précède un marqueur.

```regex
# Lookbehind — capture le nombre APRÈS "status=" sans capturer "status="
(?<=status=)\d+

# Lookahead négatif — un mot NON suivi de "="
\w+(?!=)

# Combinés — la valeur entre "ip=" et l'espace suivant
(?<=ip=)[^ ]+
```

Pièges :

- **Lookbehind de longueur variable** : beaucoup de moteurs exigent un
  lookbehind de **longueur fixe** (`(?<=abc)` OK, `(?<=a.*)` rejeté ou limité).
- **Le lookaround ne consomme rien** : enchaîner deux lookahead teste deux
  conditions au **même** point ; ce n'est pas une séquence.

## Captures : groupes capturants vs non-capturants

```regex
# Groupe capturant — alourdit la sortie si on ne réutilise pas le groupe
(error|warn|info)

# Non-capturant — pour grouper sans capturer
(?:error|warn|info)

# Nommé — lisible et robuste (l'ordre des groupes peut changer)
(?<niveau>error|warn|info)
```

Préférer les groupes **nommés** pour les extractions de champs : le nom devient
le champ, et l'ajout d'un groupe ailleurs ne décale rien.

## Échapper les métacaractères

Dans les logs, les caractères `. ( ) [ ] { } + * ? | ^ $ \` sont fréquents et
**doivent être échappés** quand on veut les matcher littéralement.

```regex
# FAUX — le point matche n'importe quel caractère
10.0.0.10            # matche aussi "10x0y0z10"

# CORRECT — point littéral échappé
10\.0\.0\.10
```

## Performance : éviter le backtracking catastrophique

Des quantificateurs imbriqués sur un motif ambigu peuvent faire exploser le
temps de calcul (ReDoS) sur certaines entrées.

```regex
# DANGER — "(a+)+" sur une longue chaîne sans match final part en explosion
(\w+)+$

# SÛR — ancrer, borner, éviter les quantificateurs imbriqués
\w+$
```

Bonnes pratiques :

- Ancrer dès que possible (`^`, `$`) pour limiter l'espace de recherche.
- Préférer `[^x]*` à `.*` / `.*?` pour borner explicitement.
- Borner les répétitions (`{1,64}`) plutôt que `+` sur des champs libres.

## Méthode pour fiabiliser une regex de log

1. Partir d'un **échantillon réel** de lignes, y compris les cas limites.
2. Construire le motif **incrémentalement**, en validant à chaque étape.
3. Ancrer et borner ; remplacer les `.*` gourmands par des classes négatives.
4. Nommer les groupes de capture.
5. Tester sur des **contre-exemples** (lignes qui ne doivent PAS matcher).

## Voir aussi

- [Formats de logs courants et leurs pièges de parsing](./formats-logs-et-pieges-parsing.md)