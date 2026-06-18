# Splunk — Concepts

Fiches expliquant le fonctionnement interne de Splunk. Cibles typiques :

- Indexers, search heads, cluster master / manager node, deployer, deployment
  server : rôles et interactions.
- **Buckets** : hot / warm / cold / frozen / thawed, transitions, nommage,
  rolling, replication factor, search factor.
- **Clustering** : cluster d'indexers, cluster de search heads, captain.
- **Multisite** : sites, replication/search factor par site, affinity de
  recherche, bascule.
- **SmartStore** : cache local, remote store, eviction, particularités vs
  stockage classique.
- Gestion du cycle de vie des données, rétention, archivage.
- Licensing, pools, fairness.

Une fiche par concept, focalisée sur les principes et les pièges, sans détail
de configuration spécifique à un environnement.

## Fiches existantes

- [Deployment Server](./deployment-server.md)
- [Cycle de vie d'un évènement : input → parsing → index → search](./cycle-de-vie-evenement.md)
- [Parsing phase : UF vs HF/indexer](./parsing-phase-uf-vs-hf.md)
- [Cycle de vie des buckets en multisite](./buckets-multisite-lifecycle.md)
- [Rebalance multisite](./rebalance-multisite.md)
- [ITSI + Federated Search](./itsi-federated-search.md)
- [Patrons de CI/CD pour déploiement Splunk](./cicd-deployment-patterns.md)
- [Déclencheurs de rolling restart : SHC & cluster d'indexers](./rolling-restart-triggers.md)
