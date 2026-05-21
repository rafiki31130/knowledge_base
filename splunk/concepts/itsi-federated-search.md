# ITSI + Federated Search

Splunk ITSI peut consommer des données via Federated Search au lieu d'une
distributed search classique. Conséquences architecturales et opérationnelles.

## Compatibilité

- Disponible à partir d'**ITSI 4.16.0**.
- **Mode transparent uniquement**.
- Recherches temps réel **non supportées**.
- Événements dans `itsi_tracked_alerts` non vus en temps réel par
  `itsi_event_grouping` : ne deviennent visibles qu'aux backfills périodiques
  du Rules Engine (~12 min).
- **Désactiver le Rules Engine** et retirer les correlation searches sur le
  federated provider distant, sinon doublons.

## Architecture cible

```
Indexer core  ←  SH simple (federated provider)  ←  SH ITSI (federated search head)
```

Vocabulaire Splunk :

- La SH qui **initie** la recherche est le « local » deployment.
- La SH **interrogée** est le « remote » provider.

Ici : ITSI = local, SH simple = remote.

## Fonctionnement du mode transparent

L'utilisateur écrit ses recherches sur le local SH comme si tout était local,
sans syntaxe spéciale. La recherche est dispatchée vers les providers
configurés.

Deux couches de permissions s'appliquent **en intersection** :

1. **Rôle de l'utilisateur sur le local SH** (ITSI) — ce qu'il a le droit de
   chercher localement.
2. **Rôle du service account sur le remote provider** (`federatedrole`) —
   filtre côté provider.

C'est l'intersection des deux qui détermine ce qui est accessible.

## Pourquoi c'est intéressant vs distributed search classique

En distributed search classique, une SH tierce non maîtrisée **ne peut pas
être restreinte côté indexer** : `srchIndexesAllowed`, `srchFilter` et autres
contraintes de rôles vivent dans le `authorize.conf` de la SH. Si on ne
contrôle pas la SH, on ne contrôle pas ces paramètres.

La federated search **inverse le modèle** : la restriction est appliquée côté
provider (qu'on contrôle), pas côté client (qu'on ne contrôle pas).
