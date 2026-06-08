# Temps dans les logs : timezones, epoch, drift d'horloge

La corrélation de sources tient ou casse sur l'horodatage. Un évènement qui
semble « en avance » sur un autre est, neuf fois sur dix, un **problème de
fuseau ou d'horloge**, pas une relation de causalité. Cette fiche couvre les
trois pièges temporels récurrents : fuseaux horaires, représentations epoch, et
dérive d'horloge.

## Le fuseau horaire : le piège n°1 de la corrélation

Un même instant s'écrit différemment selon le fuseau. `2026-06-08 14:00:00`
n'a aucun sens sans préciser **quel fuseau**.

```text
# Le même instant, trois écritures
2026-06-08T14:00:00+02:00     # heure locale avec offset (sans ambiguïté)
2026-06-08T12:00:00Z          # UTC (Z = Zulu = +00:00)
2026-06-08 14:00:00           # heure locale SANS offset (ambigu : quel fuseau ?)
```

Règles :

- **Un horodatage sans offset est ambigu.** Pour corréler deux sources, il faut
  connaître le fuseau de **chacune** — soit explicite dans la ligne, soit connu
  par configuration.
- **Normaliser vers UTC** pour comparer. C'est la seule référence commune. On
  reconvertit en heure locale seulement pour l'affichage.
- **Heure d'été / hiver (DST)** : un offset peut changer dans l'année (`+01:00`
  l'hiver, `+02:00` l'été pour un même lieu). Pendant le basculement, une heure
  locale peut exister deux fois ou pas du tout. Préférer l'offset numérique au
  nom de fuseau dans les logs.

## Epoch (temps Unix) : compter les secondes

Le temps **epoch** (ou Unix time) est le nombre de secondes écoulées depuis le
`1970-01-01T00:00:00Z`. C'est une représentation sans fuseau, idéale pour
calculer et comparer.

```text
1749391200        # secondes      → 2026-06-08T14:00:00Z
1749391200.123    # avec fraction → précision sous-seconde
1749391200000     # MILLIsecondes → piège : x1000
1749391200000000  # MICROsecondes → piège : x1 000 000
```

Pièges :

- **L'unité.** Secondes, millisecondes, microsecondes : un facteur 1000 d'écart
  projette la date en l'an 57000 ou en 1970. Repère mnémotechnique : un epoch
  **en secondes** « aujourd'hui » a **10 chiffres** ; en millisecondes, **13**.
- **UTC implicite.** L'epoch est toujours en UTC. Le convertir en heure locale
  est une opération d'**affichage**, pas de stockage.
- **Conversion en place.** Pour passer d'une chaîne lisible à de l'epoch et
  inversement (exemple Splunk) :

```spl
... | eval ts_epoch = strptime(date_brute, "%Y-%m-%dT%H:%M:%S%z")
| eval date_lisible = strftime(ts_epoch, "%Y-%m-%d %H:%M:%S %Z")
```

`%z` lit/écrit l'offset, `%Z` le nom du fuseau — les omettre, c'est rouvrir
l'ambiguïté.

## Drift d'horloge : quand les sources ne sont pas synchrones

Le **drift** (dérive) est l'écart entre l'horloge d'une source et le temps de
référence. Une source qui dérive de quelques secondes à quelques minutes décale
**tous** ses évènements, ce qui :

- casse l'ordre relatif entre sources (un effet semble précéder sa cause) ;
- fausse les fenêtres de recherche (évènements « manquants » ou en double) ;
- rend les `transaction` et corrélations temporelles non fiables.

Causes typiques : NTP absent ou en échec, machine virtuelle suspendue/reprise,
horloge matérielle défaillante, fuseau mal configuré (qui ressemble à un drift
de plusieurs heures).

Détection : comparer, pour une même source, l'horodatage **de l'évènement** et
l'horodatage **de réception/indexation**. Un écart structurel (toujours dans le
même sens, du même ordre) signe une dérive plutôt qu'un retard ponctuel de
collecte.

> En contexte Splunk, c'est exactement la distinction entre `_time` (horodatage
> de l'évènement) et `_indextime` (réception). Voir
> [`_time` vs `_indextime` : ne pas les confondre](../splunk/spl/time-vs-indextime.md)
> pour la matérialisation du délai et le piège de la fenêtre de recherche.

## Méthode pour fiabiliser une corrélation temporelle

1. **Identifier le fuseau de chaque source** (explicite ou par config).
2. **Normaliser vers UTC** avant toute comparaison.
3. **Vérifier l'unité** des champs epoch (secondes / ms / µs).
4. **Estimer le drift** par source (écart évènement ↔ réception) avant de
   conclure à une causalité sur la base de l'ordre.
5. **Garder une marge** : ne pas traiter un écart de quelques secondes entre
   deux sources comme significatif tant que la synchro n'est pas établie.

## À retenir

- Un horodatage sans offset est ambigu ; normaliser en UTC pour comparer.
- Epoch = secondes depuis 1970, en UTC ; toujours vérifier l'unité (10 chiffres
  ≈ secondes, 13 ≈ millisecondes).
- Un évènement « en avance » est d'abord un suspect de drift/fuseau, pas une
  causalité.

## Voir aussi

- [`_time` vs `_indextime` : ne pas les confondre](../splunk/spl/time-vs-indextime.md)
- [Formats de logs courants et leurs pièges de parsing](./formats-logs-et-pieges-parsing.md)
- [Encodages à reconnaître et décoder : base64, URL, hex](./encodages-courants.md)
