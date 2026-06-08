# Triage d'alerte : qualifier / déqualifier

Un flux d'alertes contient toujours plus de bruit que de signal. Le triage est
la décision **rapide et reproductible** de savoir si une alerte mérite une
investigation (la *qualifier*) ou peut être écartée (la *déqualifier*) — sans s'y
noyer ni écarter à tort un vrai positif. Cette fiche décrit un patron de
raisonnement générique, sans outil ni source nommés.

## Le but du triage

Le triage **n'est pas** l'investigation. Son seul objectif : trancher entre trois
sorties, en quelques minutes, sur la base d'éléments observables.

```text
        ┌──────────────┐
        │   ALERTE     │
        └──────┬───────┘
               ▼
        ┌──────────────┐
        │   TRIAGE     │  Décision rapide, critères fixes
        └──┬────┬────┬─┘
           ▼    ▼    ▼
       QUALIFIER  DÉQUALIFIER  ESCALADER
       (enquêter) (clore+motif) (info insuffisante)
```

La troisième sortie (escalader / mettre en attente) est légitime : forcer une
décision binaire quand l'information manque produit des erreurs.

## Questions de triage (dans l'ordre)

Un ordre fixe rend le triage reproductible d'une alerte à l'autre et d'une
personne à l'autre.

1. **L'alerte est-elle bien formée ?** A-t-elle les champs minimaux pour décider
   (quoi, qui/quoi est concerné, quand, source) ? Une alerte tronquée part en
   escalade, pas en déqualification.
2. **Est-ce un faux positif connu ?** Correspond-elle à un motif déjà documenté
   comme bénin (cf. base de cas connus) ? Si oui → déqualifier avec le motif.
3. **Le contexte la rend-il attendue ?** Activité planifiée, fenêtre de
   maintenance, comportement normal pour cet acteur/cet horaire ? Si oui →
   déqualifier en notant le contexte.
4. **Y a-t-il corroboration ?** Une seconde source indépendante va-t-elle dans le
   même sens ? Une alerte isolée est plus faible qu'une alerte corroborée.
5. **Quel serait l'impact si elle était vraie ?** Même peu probable, un impact
   élevé justifie de qualifier par prudence.

## Critères pour DÉQUALIFIER

Déqualifier = clore **avec un motif explicite et réutilisable**. Une
déqualification sans motif est ingérable (impossible à auditer, à industrialiser).

- **Faux positif connu** : motif déjà répertorié → référencer la règle/cas.
- **Activité attendue** : changement planifié, tâche périodique, comportement
  normal de l'acteur sur cette fenêtre.
- **Donnée non concluante mais à faible impact** : signal trop faible et enjeu
  négligeable.
- **Doublon** : même évènement déjà couvert par une autre alerte en cours.

Toujours **écrire le motif** : il alimente la base de faux positifs et permet de
tuner la règle à la source.

## Critères pour QUALIFIER

Qualifier = ouvrir une investigation. Indices qui font pencher de ce côté :

- **Convergence multi-sources** : plusieurs signaux indépendants concordent.
- **Écart au profil de base** : comportement inhabituel pour cet acteur, cet
  hôte, cet horaire (`user01` actif à un moment hors de son profil habituel).
- **Impact potentiel élevé** : la cible ou l'action a des conséquences sérieuses
  si l'hypothèse se confirme.
- **Absence d'explication bénigne** : aucun contexte connu ne la justifie.
- **Récurrence / progression** : l'alerte se répète ou s'intensifie.

En cas de qualification, le triage passe le relais à la
[boucle d'investigation](./boucle-investigation.md) : formuler la première
question, poser une hypothèse testable, requêter, pivoter.

## Réduire le bruit à la source

Le triage révèle des motifs ; les exploiter améliore le flux en amont :

- **Faux positifs récurrents** → ajuster la règle de détection (seuil, exclusion
  ciblée et documentée), pas masquer à la main à chaque fois.
- **Manque de contexte récurrent** → enrichir l'alerte (champs d'identité,
  d'actif, de criticité) pour décider plus vite.
- **Doublons** → corréler/regrouper les alertes liées avant qu'elles n'arrivent
  au triage.

## Pièges du triage

- **Déqualifier sans motif** : impossible à auditer, ne tune rien.
- **Biais d'habitude** : « c'est toujours un faux positif » finit par masquer le
  vrai positif. Réévaluer périodiquement les motifs de déqualification.
- **Sur-qualifier par prudence** : qualifier tout sature la capacité
  d'investigation et noie le vrai signal autant que le bruit.
- **Trancher sur une alerte mal formée** : sans champs minimaux, escalader plutôt
  que deviner.

## À retenir

- Le triage tranche vite ; il ne mène pas l'enquête.
- Trois sorties : qualifier, déqualifier (toujours avec motif), escalader si
  l'info manque.
- Qualifier sur convergence, écart au profil, impact, absence d'explication
  bénigne.
- Chaque motif de déqualification est une donnée : il sert à réduire le bruit à
  la source.

## Voir aussi

- [La boucle d'investigation : question → hypothèse → requête → pivot](./boucle-investigation.md)
- [Pivots classiques : user → host → process → network → file](./pivots-investigation.md)
