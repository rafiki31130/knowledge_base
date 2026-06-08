# Formats de logs courants et leurs pièges de parsing

Avant de parser une source, il faut **reconnaître son format**. Chaque famille
de logs a une structure et des pièges propres ; appliquer le mauvais modèle de
parsing produit des champs vides, des évènements coupés ou des timestamps faux.
Cette fiche couvre les formats les plus fréquents et l'erreur typique de chacun.

## Syslog (RFC 3164 et RFC 5424)

Deux variantes coexistent et ne se parsent pas pareil.

```text
# RFC 3164 (BSD, ancien) — pas d'année, pas de fuseau
<134>Oct 11 22:14:15 host01 sshd[1234]: message

# RFC 5424 (moderne) — timestamp ISO 8601 avec fuseau
<134>1 2026-06-08T22:14:15.003Z host01 sshd 1234 - - message
```

Pièges :

- **RFC 3164 n'a pas d'année** : le parser la déduit (souvent l'année courante),
  ce qui casse au passage du 31 décembre et lors d'un rejeu d'anciens fichiers.
- **Pas de fuseau en RFC 3164** : le `_time` dépend du fuseau supposé du
  collecteur. Source classique d'évènements « décalés ».
- Le **priority** `<134>` encode facility + severity ; le décoder pour filtrer
  par sévérité.

## CEF (Common Event Format) et LEEF

Formats à champs nommés, souvent transportés **dans** un message syslog.

```text
# CEF — en-tête à pipes, puis extension clé=valeur
CEF:0|Vendor|Product|1.0|100|Connexion refusee|5|src=10.0.0.10 dst=10.0.0.20 spt=51000

# LEEF — en-tête, puis paires séparées par tab (\t) par défaut
LEEF:2.0|Vendor|Product|1.0|100|src=10.0.0.10	dst=10.0.0.20
```

Pièges :

- **Échappement dans l'en-tête CEF** : un `|` ou un `\` littéral dans un champ
  doit être échappé (`\|`, `\\`). Un parser naïf coupe l'en-tête au mauvais
  endroit.
- **Séparateur LEEF variable** : tab par défaut, mais redéfinissable. Vérifier
  avant d'écrire l'extraction.
- L'enveloppe syslog ajoute son propre timestamp : décider lequel fait foi
  (celui de l'évènement CEF/LEEF, en général).

## JSON

Lisible, mais piégeux dès que la structure n'est pas plate.

```json
{"ts":"2026-06-08T22:14:15Z","user":"user01","action":"login","meta":{"ip":"10.0.0.10","ok":true}}
```

Pièges :

- **JSON imbriqué** : `meta.ip` n'est pas extrait automatiquement comme champ
  plat par tous les parsers ; prévoir l'aplatissement.
- **JSON multiligne ou « pretty-printed »** : un évènement = un objet ; si le
  JSON est indenté sur plusieurs lignes, le découpage par ligne casse tout.
  Préférer un évènement par ligne (NDJSON).
- **Logs mixtes** : un préfixe texte suivi d'un objet JSON (`... msg={...}`)
  exige d'isoler la partie JSON avant de la parser.
- **Types** : `"ok":true` (booléen) vs `"ok":"true"` (chaîne) — la comparaison
  diffère.

## Windows Event Log

Évènements structurés (XML sous-jacent), volumineux, multilignes.

Pièges :

- **Multiligne par nature** : le découpage des évènements ne peut pas se faire
  « une ligne = un évènement ». S'appuyer sur le délimiteur d'évènement, pas sur
  le saut de ligne.
- **EventID seul est ambigu** : le même `EventID` a un sens différent selon le
  `Channel` / `Provider`. Toujours qualifier par la source.
- **Messages localisés** : le texte d'un évènement peut être traduit selon la
  langue de l'hôte. Filtrer sur l'`EventID` et les champs structurés, pas sur le
  texte humain.

## Audit Linux (auditd)

Format clé=valeur, mais un évènement logique est **éclaté sur plusieurs lignes**
partageant un même identifiant.

```text
type=SYSCALL msg=audit(1717881255.003:4242): arch=c000003e syscall=59 ... uid=1000
type=EXECVE  msg=audit(1717881255.003:4242): argc=2 a0="ls" a1="-l"
type=PATH    msg=audit(1717881255.003:4242): name="/usr/bin/ls" ...
```

Pièges :

- **Corrélation par `msg=audit(<timestamp>:<id>)`** : les lignes d'un même
  évènement partagent le couple `(timestamp:id)`. Les regrouper avant analyse,
  sinon on lit des fragments.
- **Timestamp en epoch** dans le champ `msg`, pas en début de ligne.
- **Valeurs encodées en hex** : certains champs (chemins, arguments avec
  caractères spéciaux) sont en hexadécimal et doivent être décodés.

## Méthode générale

1. **Identifier le format** à l'œil avant d'écrire la moindre extraction.
2. **Fixer le découpage des évènements** (1 ligne = 1 évènement ? multiligne ?
   regroupement par identifiant ?) — c'est l'erreur n°1.
3. **Fixer le timestamp** : lequel fait foi, dans quel fuseau ? (voir le
   décalage `_time` / heure d'arrivée).
4. **Extraire les champs**, en gérant l'échappement et l'imbrication.
5. **Valider sur un échantillon** représentatif (cas limites : valeurs vides,
   caractères spéciaux, lignes tronquées).

## Voir aussi

- [Regex pour les logs : greedy, ancres, lookaround](./regex-pour-logs.md)
- [`_time` vs `_indextime` : ne pas les confondre](../splunk/spl/time-vs-indextime.md)
- [Parsing phase : UF vs HF/indexer](../splunk/concepts/parsing-phase-uf-vs-hf.md)
