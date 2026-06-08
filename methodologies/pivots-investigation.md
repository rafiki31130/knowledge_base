# Pivots classiques : user → host → process → network → file

Investiguer, c'est passer d'un indice établi à l'indice suivant. Un **pivot**,
c'est utiliser une valeur trouvée sur un axe (un utilisateur, un hôte, un
processus…) comme point d'entrée pour interroger un autre axe. Cinq axes
reviennent constamment, et ils s'enchaînent dans les deux sens. Cette fiche est
un schéma conceptuel illustré d'exemples abstraits, sans cas réel.

## Les cinq axes

```text
   USER ◄──► HOST ◄──► PROCESS ◄──► NETWORK ◄──► FILE
   (qui)    (où)      (quoi tourne) (vers où)   (sur quoi)
```

Les flèches vont dans les deux sens : un pivot n'a pas de direction imposée. On
entre par l'axe où se trouve l'indice de départ et on rebondit selon la question
du moment.

| Axe | Question | Clés de pivot typiques |
| --- | --- | --- |
| **user** | Qui ? | identité (cf. SID/UPN/`sub`), compte, session |
| **host** | Où ? | nom d'hôte, identifiant d'actif, adresse |
| **process** | Quoi s'exécute ? | nom/chemin de processus, identifiant de processus, parent |
| **network** | Vers/depuis où ? | adresse, port, domaine, flux |
| **file** | Sur quel objet ? | chemin, nom, empreinte, objet manipulé |

## Les pivots, axe par axe

### user → host

À partir d'un utilisateur, lister **où** il a été actif sur une fenêtre.

- Question : « sur quels hôtes `user01` s'est-il authentifié entre T1 et T2 ? »
- Sortie : une liste d'hôtes → chacun devient un point d'entrée pour `host`.

### host → process

À partir d'un hôte, lister **ce qui s'y est exécuté**.

- Question : « quels processus se sont lancés sur `host-01` autour de T ? »
- Attention à la **filiation** : remonter le processus **parent** est souvent
  plus parlant que le processus lui-même.

### process → network

À partir d'un processus, regarder **ses connexions**.

- Question : « ce processus a-t-il ouvert des connexions sortantes ? vers quoi ? »
- Sortie : adresses/domaines → pivot vers `network` (et potentiellement un autre
  `host`).

### network → host / user

À partir d'un indicateur réseau, **remonter** vers les machines et comptes
concernés.

- Question : « quels hôtes ont communiqué avec `10.0.0.0/24` (ou
  `example.com`) ? » puis « quels comptes étaient actifs sur ces hôtes au même
  moment ? »

### process / host → file

À partir d'un processus ou d'un hôte, regarder **les fichiers** créés, lus,
modifiés.

- Question : « quels fichiers ce processus a-t-il écrits ? »
- L'**empreinte** (hash) d'un fichier est un excellent pivot transverse : la même
  empreinte sur plusieurs hôtes relie des évènements indépendants.

## Le fil temporel : le pivot implicite

Tout pivot se fait **dans une fenêtre de temps**. Élargir ou resserrer la fenêtre
est en soi un pivot :

- Resserrer autour de l'instant d'un indice pour voir ce qui l'entoure.
- Élargir pour trouver la **première occurrence** (`earliest`) — depuis quand ce
  comportement existe-t-il ?

La fiabilité de l'enchaînement dépend de l'**alignement temporel** des sources :
un drift d'horloge casse l'ordre des pivots. Voir
[Temps dans les logs : timezones, epoch, drift d'horloge](../concepts/temps-dans-les-logs.md).

## Exemple déroulé (fictif)

| Tour | Axe d'entrée | Pivot | Vers | Indice obtenu |
| --- | --- | --- | --- | --- |
| 1 | user (`user01`) | user → host | host | actif sur `host-01`, inhabituel |
| 2 | host (`host-01`) | host → process | process | un processus lancé hors horaire |
| 3 | process | process → network | network | connexion sortante vers une cible jamais vue |
| 4 | network | network → host | host | un 2ᵉ hôte a contacté la même cible |
| 5 | process | process → file | file | un fichier écrit ; son empreinte se retrouve sur le 2ᵉ hôte |

Chaque ligne réutilise une valeur trouvée à la précédente. La timeline se
construit pivot après pivot.

## Discipline des pivots

- **Conserver la provenance de chaque valeur** : noter d'où vient chaque clé de
  pivot évite les rapprochements faux (deux `user01` de référentiels différents
  ne sont pas la même personne — voir
  [Identités dans les logs](../concepts/identites-dans-les-logs.md)).
- **Normaliser les clés avant de pivoter** : casse, fuseau, forme d'identifiant.
  Un pivot sur des valeurs non normalisées rate des correspondances.
- **Distinguer fait et lien supposé** : « le même hash sur deux hôtes » est un
  fait ; « donc c'est la même action » est une interprétation à étayer.
- **Borner le temps à chaque pivot** : un pivot sans fenêtre ramène trop de bruit.

## À retenir

- Cinq axes — user, host, process, network, file — reliés dans les deux sens.
- Un pivot réutilise une valeur d'un axe comme clé d'entrée d'un autre.
- Le temps est le pivot implicite : toujours borner la fenêtre, se méfier du
  drift.
- Normaliser les clés et tracer leur provenance pour éviter les faux
  rapprochements.

## Voir aussi

- [La boucle d'investigation : question → hypothèse → requête → pivot](./boucle-investigation.md)
- [Triage d'alerte : qualifier / déqualifier](./triage-alerte.md)
- [Identités dans les logs : SID, UPN, sAMAccountName, notions OIDC](../concepts/identites-dans-les-logs.md)
- [Temps dans les logs : timezones, epoch, drift d'horloge](../concepts/temps-dans-les-logs.md)
