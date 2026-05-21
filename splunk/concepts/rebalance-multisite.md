# Rebalance d'un cluster d'indexeurs (multisite)

Deux opérations distinctes, souvent confondues.

## Data rebalance vs primary rebalance

| Opération | Commande | Effet | Transfert de données |
|---|---|---|---|
| **Data rebalance** | `splunk rebalance cluster-data` | Redistribue les copies de buckets entre peers pour équilibrer la charge disque. | Oui. |
| **Primary rebalance** | `splunk rebalance cluster-primaries` | Redistribue uniquement la désignation de copie primaire entre les copies existantes. Sert à équilibrer la charge de recherche. | Non. |

Les deux opérations respectent `site_replication_factor` et
`site_search_factor` en multisite.

## Commandes principales (à exécuter sur le CM)

```
splunk rebalance cluster-data -action start \
    [-searchable true|false] \
    [-max_runtime <min>] \
    [-threshold <0.0-1.0>] \
    [-site <site_id>]

splunk rebalance cluster-data -action status
splunk rebalance cluster-data -action stop

splunk rebalance cluster-primaries [-site <site_id>]
```

## Options critiques

- `-searchable true` — **indispensable en production**. Maintient la
  searchabilité pendant l'opération en déplaçant les copies une par une avec
  promotion préalable d'une autre copie en primaire. Sans cette option, des
  buckets peuvent devenir non-searchable transitoirement.
- `-threshold` (défaut `0.9`) — un peer est considéré équilibré si son nombre
  de buckets est entre `threshold × moyenne` et `moyenne / threshold`. Valeur
  proche de 1 ⇒ équilibrage strict et lent. Valeur trop basse ⇒ rebalance
  superficiel.
- `-max_runtime` — limite dure en minutes. À expiration, le rebalance s'arrête
  proprement, état partiel conservé.

## À lire à côté

- [Cycle de vie des buckets en multisite](./buckets-multisite-lifecycle.md) —
  comprendre ce que les contraintes de site impliquent pour le rebalance.
