# Hypothèses concurrentes et qualité de preuve

Une investigation déraille rarement faute de données : elle déraille parce qu'on
**se fixe trop tôt** sur une explication, puis qu'on ne cherche plus que ce qui
la confirme. La parade tient en deux disciplines : tenir **plusieurs hypothèses
de front** jusqu'à ce que la preuve les départage, et savoir **peser la qualité**
de cette preuve plutôt que sa simple présence.

Cette fiche est le pendant analytique de
[La boucle d'investigation](./boucle-investigation.md), qui décrit le mouvement
question → hypothèse → requête → pivot. Ici on s'attarde sur **l'étape
hypothèse/requête** : comment éviter le biais de confirmation et noter la force
d'un indice. On ne réexplique pas la boucle — on la suppose connue.

## Tenir plusieurs hypothèses en parallèle

Pour un même fait observé, lister **dès le départ** les explications plausibles
et concurrentes — au minimum une « bénigne » et une « préoccupante ». Tant
qu'aucune preuve ne tranche, **aucune n'est privilégiée**.

Exemple : un compte `user01` se connecte depuis une source jamais vue.

| # | Hypothèse | Statut initial |
| --- | --- | --- |
| H1 | Poste légitime ayant changé d'adresse (DHCP, autre site) | ouverte |
| H2 | Erreur de configuration (proxy, NAT, `example.com` mal résolu) | ouverte |
| H3 | Accès non autorisé | ouverte |

Le réflexe à combattre : choisir H3 parce qu'elle est la plus « intéressante »,
puis ne chercher que ce qui la conforte. Une bonne requête doit pouvoir
**éliminer** une hypothèse, pas seulement en nourrir une.

## La requête diagnostique : chercher ce qui discrimine

La requête la plus utile n'est pas celle qui confirme l'hypothèse favorite,
c'est celle dont le **résultat sépare** les hypothèses concurrentes. On la
choisit en se demandant, avant de la lancer : « selon le résultat, quelle(s)
hypothèse(s) cela élimine-t-il ? »

| Observation cherchée | Si présent | Si absent |
| --- | --- | --- |
| Historique de la même source pour `user01` avant aujourd'hui | affaiblit H3, renforce H1 | renforce H3 |
| Changement de config réseau corrélé dans le temps | renforce H2 | affaiblit H2 |
| Autres comptes vus depuis la même source | reclasse le problème (pivot) | garde le focus sur `user01` |

Un test qui ne peut **rien éliminer** quel que soit son résultat ne fait pas
avancer l'investigation : c'est du bruit confirmatoire.

## Le biais de confirmation, concrètement

C'est la tendance à ne formuler que des requêtes qui valident l'idée de départ,
et à interpréter tout résultat ambigu en sa faveur. Quelques garde-fous :

- **Écrire l'hypothèse adverse.** Pour chaque hypothèse, formuler explicitement
  ce qui l'**infirmerait** — et aller chercher ce contre-exemple.
- **Présomption d'explication bénigne.** Traiter l'explication banale (config,
  erreur, comportement légitime) comme l'hypothèse par défaut à réfuter avant de
  conclure au pire.
- **Noter les hypothèses écartées et pourquoi.** Évite d'y revenir en boucle et
  documente le raisonnement pour un relecteur.
- **Distinguer fait et interprétation.** « La source est `10.0.0.0/24` » est un
  fait ; « c'est une compromission » est une interprétation à étayer.

## Niveaux de preuve : tout indice ne se vaut pas

Confirmer une hypothèse, ce n'est pas accumuler des indices faibles : c'est
réunir une preuve dont la **qualité** soutient la conclusion. Quelques axes pour
peser un indice.

**Force de l'indice**

| Niveau | Caractéristique | Exemple |
| --- | --- | --- |
| Fort | Direct, journalisé par une source fiable, difficile à falsifier | log d'authentification serveur signé/centralisé |
| Moyen | Indirect mais cohérent, recoupable | corrélation temporelle entre deux sources |
| Faible | Circonstanciel, interprétable de plusieurs façons | « ça ressemble à un schéma déjà vu » |

**Critères de qualité, au-delà de la force**

- **Source.** Qui a produit la donnée, est-elle altérable par l'acteur observé ?
  Un log côté serveur de confiance vaut mieux qu'un log côté machine suspecte.
- **Indépendance.** Deux indices issus de la **même** source ne se confirment pas
  mutuellement : c'est le même point de défaillance. La convergence ne compte que
  si les sources sont indépendantes.
- **Réfutabilité.** Une preuve qui ne pouvait *que* sortir positive n'établit
  rien (cf. requête diagnostique).
- **Absence de preuve ≠ preuve d'absence.** Ne pas trouver de trace peut signifier
  « rien ne s'est passé » **ou** « la journalisation ne couvre pas ce cas ». Vérifier
  la couverture avant de conclure de l'absence.

## Conclure : quand une hypothèse l'emporte

On clôt quand **une** hypothèse est soutenue par une preuve de qualité
suffisante **et** que les concurrentes ont été activement réfutées — pas
seulement « pas confirmées ». Si la preuve disponible ne permet de départager
aucune, c'est aussi un résultat valable : on documente l'incertitude et ce qu'il
faudrait comme donnée (souvent absente) pour trancher.

## Voir aussi

- [La boucle d'investigation : question → hypothèse → requête → pivot](./boucle-investigation.md) — le cycle dans lequel s'insèrent ces hypothèses
- [Triage d'alerte : qualifier / déqualifier](./triage-alerte.md) — décider vite si une alerte mérite cette analyse
- [Pivots classiques : user → host → process → network → file](./pivots-investigation.md) — passer d'un indice établi au suivant