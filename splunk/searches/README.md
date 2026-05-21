# Recherches d'investigation

Recherches Splunk **génériques**, paramétrables, utiles pour une catégorie de
cas d'investigation. Pas de requête extraite d'un environnement réel.

## Format conseillé pour une fiche

1. **Cas d'usage** — quelle question on cherche à répondre.
2. **Sources de données attendues** — type de logs, sourcetypes génériques,
   champs requis (`src`, `dest`, `user`, `action`…).
3. **Recherche** — bloc SPL avec placeholders (`<index>`, `<user>`, `<window>`).
4. **Lecture du résultat** — ce que chaque colonne signifie, ce qui doit
   alerter.
5. **Variantes** — pivots possibles, élargissements, restrictions.
6. **Limites / faux positifs connus**.

## Règles

- Pas de nom d'environnement, d'index réel, d'utilisateur réel, d'IP réelle.
- Pas de seuils issus d'un client : si un seuil est cité, expliquer comment le
  calibrer plutôt que donner « la » valeur.
- Pas de TTP attribuée à un acteur précis sans source publique citée.

## Fiches existantes

- [Détecter les buckets sous RF/SF](./buckets-degrades-detection.md)
