# Cycle de vie des buckets en cluster multisite

Comment un cluster d'indexeurs multisite réagit à la saturation d'un peer
(volume cold plein), et en quoi c'est différent d'un freeze par rétention.

## Saturation d'un peer (volume cold plein)

**Déclencheur** : `maxVolumeDataSizeMB` atteint sur un peer.

Séquence :

1. Le peer **gèle localement** les buckets les plus anciens du volume (tous
   index confondus partageant ce volume), jusqu'à repasser sous le seuil.
   Critère : `latest event time` le plus ancien.
   Les politiques de rétention par index (`frozenTimePeriodInSecs`,
   `maxTotalDataSizeMB`) sont **court-circuitées**.
2. La copie locale est supprimée (ou archivée si `coldToFrozenDir` /
   `coldToFrozenScript` est configuré). Ce gel est **local et asymétrique** :
   les autres copies du même bucket sur les autres peers ne sont pas touchées.
3. Le Cluster Manager détecte la perte de copie, passe le cluster en
   `not met`, déclenche un fixup.
4. **Fixup** : réplication depuis un peer survivant vers un peer cible
   éligible, en respectant `site_replication_factor` et `site_search_factor`.
5. **Si aucun peer cible éligible** (saturation globale, contrainte de site
   impossible à satisfaire) → cluster reste en `not met` indéfiniment.

## Différence avec le freeze par rétention

- **Freeze par rétention** : coordonné cluster-wide. Toutes les copies du
  bucket sont gelées simultanément, **pas de fixup déclenché**.
- **Freeze par saturation de volume** : local à un peer. Provoque la réaction
  cluster décrite ci-dessus.

## Risque de cascade

Le fixup transfère des données vers les peers cibles, qui peuvent à leur tour
atteindre leur limite et geler d'autres buckets. En multisite, le pool de
cibles éligibles est réduit par la contrainte de site, ce qui aggrave le
risque.

## Absence de seuil natif d'exclusion pré-saturation

Pas de mécanisme natif pour exclure un peer des fixups avant qu'il atteigne
100 % d'usage. Les paramètres `max_peer_build_load` et `max_peer_rep_load`
(section `[clustering]` du `server.conf` du CM) limitent le **parallélisme**
des fixups mais **n'implémentent pas un seuil de capacité**.

## À lire à côté

- [Rebalance multisite](./rebalance-multisite.md) — outils pour redistribuer
  avant saturation.
- [Détection des buckets sous RF/SF](../searches/buckets-degrades-detection.md)
  — diagnostic post-incident.
