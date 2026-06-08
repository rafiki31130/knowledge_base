# La boucle d'investigation : question → hypothèse → requête → pivot

Une investigation n'est pas une requête magique qui « trouve la réponse », mais
une **boucle** d'hypothèses testées les unes après les autres. Formaliser cette
boucle évite deux écueils symétriques : tourner en rond dans les données sans
direction, et se fixer trop tôt sur une seule explication.

## Les quatre temps de la boucle

```text
        ┌─────────────┐
        │  QUESTION   │  Que cherche-t-on à établir ?
        └──────┬──────┘
               ▼
        ┌─────────────┐
        │ HYPOTHÈSE   │  Explication plausible et TESTABLE
        └──────┬──────┘
               ▼
        ┌─────────────┐
        │  REQUÊTE    │  Donnée qui confirme OU infirme l'hypothèse
        └──────┬──────┘
               ▼
        ┌─────────────┐
        │   PIVOT     │  Le résultat ouvre la question suivante
        └──────┬──────┘
               │
               └──────────► retour à QUESTION (boucle)
```

### 1. Question

Une investigation commence par une **question précise**, pas par « regarder les
logs ». Une bonne question est bornée et a une réponse vérifiable.

- Trop vague : « est-ce que `user01` a fait quelque chose de suspect ? »
- Exploitable : « `user01` s'est-il connecté depuis une source inhabituelle
  entre 22:00 et 23:00 ? »

### 2. Hypothèse

Formuler une explication **plausible et testable**. Une hypothèse qu'aucune
donnée ne pourrait infirmer est inutile.

- Exemple : « la connexion vient d'un poste légitime de `user01` qui a changé
  d'adresse (10.0.0.0/24 → autre sous-réseau interne). »
- Tenir **plusieurs hypothèses concurrentes** de front (légitime / erreur de
  config / activité non autorisée) jusqu'à ce que la donnée tranche.

### 3. Requête

Construire la requête qui **confirme OU infirme** l'hypothèse — pas celle qui ne
fait que la conforter. La donnée recherchée doit pouvoir donner les deux
réponses.

- Mauvais réflexe : ne chercher que ce qui valide l'idée de départ (biais de
  confirmation).
- Bon réflexe : chercher aussi le contre-exemple (« y a-t-il d'autres
  connexions de ce poste avant cette date ? »).

### 4. Pivot

Le résultat ne « clôt » presque jamais l'investigation : il **ouvre la question
suivante**. Le pivot, c'est passer d'un indice établi à l'axe d'analyse suivant.

- Réponse obtenue : « la source est un hôte interne, `host=srv-app-01`. »
- Pivot : « quels autres comptes se sont authentifiés depuis `srv-app-01` sur la
  même fenêtre ? » → nouvelle question, la boucle recommence.

## Exemple déroulé (fictif)

| Tour | Question | Hypothèse | Requête (forme) | Résultat | Pivot |
| --- | --- | --- | --- | --- | --- |
| 1 | D'où vient la connexion de `user01` à 22:15 ? | Depuis un poste interne habituel | filtrer les auth de `user01` sur la fenêtre, lister les sources | source = un hôte jamais vu pour ce compte | → enquêter sur cet hôte |
| 2 | Cet hôte est-il légitime ? | C'est un serveur interne mal documenté | rechercher l'historique d'activité de l'hôte | l'hôte n'a aucune activité avant ce jour | → enquêter sur l'apparition de l'hôte |
| 3 | Depuis quand cet hôte émet-il ? | Premier signe = aujourd'hui | borner par première occurrence (`earliest`) | première trace il y a 2 h | → corréler avec d'autres comptes |

À chaque tour : une question, une hypothèse testable, une requête qui peut
infirmer, un pivot. La timeline se reconstruit boucle après boucle.

## Discipline qui fait la différence

- **Écrire la question avant la requête.** Si on ne sait pas formuler la
  question, la requête sera floue.
- **Noter chaque hypothèse écartée** et pourquoi : ça évite d'y revenir et
  documente le raisonnement.
- **Distinguer fait et interprétation.** « La connexion vient de `srv-app-01` »
  est un fait ; « c'est une intrusion » est une interprétation à étayer.
- **Savoir s'arrêter.** La boucle se termine quand la question initiale a une
  réponse étayée — ou quand on a établi qu'on ne peut pas y répondre avec les
  données disponibles (résultat valable lui aussi).

## Voir aussi

- [`stats` vs `eventstats` vs `streamstats`](../splunk/spl/stats-eventstats-streamstats.md) — outiller les requêtes d'une boucle
- [Formats de logs courants et leurs pièges de parsing](../concepts/formats-logs-et-pieges-parsing.md)
