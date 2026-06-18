# Chapitre 7 — Pièges et anti-patterns

> Ce chapitre consolide les pièges récurrents et les anti-patterns architecturaux observés autour des trois bundles Splunk. Un **anti-pattern** est une décision à éviter ; un **piège** est un comportement Splunk inattendu auquel il faut s'attendre. Les deux familles sont séparées : on ne « corrige » pas un piège, on apprend à vivre avec ; on retire un anti-pattern de l'architecture.

## Rappels rapides

- Les anti-patterns sont des **décisions** prises par un admin ou un développeur d'app. Ils se retirent.
- Les pièges sont des **comportements Splunk** qui ne sont pas des bugs mais des subtilités. Ils s'apprennent.
- La distinction est utile pour le débrief d'incident : « on a accumulé un anti-pattern » est un sujet de gouvernance ; « on est tombé sur un piège » est un sujet de formation.

## 1. Anti-patterns côté contenu (`etc/shcluster/apps/` et apps Splunk)

### A1 — Apps trop grosses dans `etc/shcluster/apps/`

Une app monolithique de plusieurs centaines de Mo dans `etc/shcluster/apps/` cumule deux coûts : le push deployer → captain est lent (chaque apply), et l'arbre est intégralement parcouru à chaque cycle de conf replication interne SHC. Au-delà de 200 Mo cumulés dans `etc/shcluster/apps/`, l'admin sent l'apply ralentir. Au-delà de 500 Mo, il commence à éviter les apply.

**Symptôme.** Apply de 5+ minutes, cycles de conf replication qui se chevauchent, captain qui se plaint dans `splunkd.log`.

**Retrait.** Splitter par app fonctionnelle ; sortir les data embarquées (cf. A2 ci-dessous) ; supprimer les apps mortes ou désactivées ; consolider les `local/savedsearches.conf` qui dupliquent du contenu.

### A2 — Lookups en clair poussées par le deployer

Une lookup `historical_dump.csv` de plusieurs centaines de Mo embarquée dans `etc/shcluster/apps/<app>/lookups/` est doublement coûteuse : elle gonfle le bundle SHC (apply deployer) et elle gonfle le knowledge bundle SH → peers (à chaque cycle). Dans un SHC + indexer cluster non négligeable, c'est dizaines de Go de réplication par jour inutiles.

**Symptôme.** Bundle SHC ou knowledge bundle qui dépasse plusieurs centaines de Mo sans justification métier ; cycles de réplication knowledge bundle qui prennent du temps.

**Retrait.** Trois options : (a) Externaliser la lookup en index dédié et utiliser `lookup` distribué ou `tstats` ; (b) Externaliser en KV Store partagé ; (c) Réduire en amont (filtrer, partitionner). L'option (a) est généralement la plus simple en infra existante.

### A3 — `.git` ou métadonnées de build dans une app

Une app packagée à partir d'un clone git sans clean propre embarque `.git/`, `node_modules/`, `__pycache__/`, ou des artefacts de build. Le bundle gonfle sans raison fonctionnelle.

**Symptôme.** `du -sh $SPLUNK_HOME/etc/apps/<app>/.git` retourne plusieurs Mo.

**Retrait.** Nettoyer le packaging (`.tar.gz` ou `.spl` propre). Ajouter `static/`, `appserver/`, `bin/__pycache__/`, `.git/` à la `replicationBlacklist` comme garde-fou.

### A4 — `local/` versionné côté deployer pour ce qui devrait être dans `default/`

L'admin qui modifie un `default/savedsearches.conf` côté deployer mais le sauvegarde dans `local/` confond la sémantique : `default/` est la baseline portée par l'app, `local/` est l'override local. Versionner systématiquement `local/` à côté de `default/` brouille les overrides intentionnels (faits par les membres au runtime) avec les configurations centrales.

**Symptôme.** Conflits silencieux entre `local/` poussé par deployer et `local/` créé localement sur un membre ; impossibilité de tracer qui a écrit quoi.

**Retrait.** Convention : `default/` dans `etc/shcluster/apps/<app>/`, et `local/` réservé aux overrides explicitement centralisés (par exemple un `local/savedsearches.conf` qui surcharge une savedsearch du `default/` avec un paramètre spécifique au site).

## 2. Anti-patterns côté topologie

### A5 — Refuser cascading à 30 peers

Au-delà de 15-20 peers, Splunk recommande cascading ([Cascadingknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.1/DistSearch/Cascadingknowledgebundlereplication)). Garder le mode classique à 30 peers par confort cumule un coût de bande passante et de latence. Le pousse-à-bout : l'admin augmente `replicationThreads` et `sendRcvTimeout` pour masquer, sans gain réel.

**Symptôme.** Cycles de push qui prennent plusieurs minutes, bande passante saturée pendant les cycles, recherches qui attendent.

**Retrait.** Basculer en cascading. C'est un changement de configuration, pas un changement d'architecture (les peers restent les mêmes). Tester sur un site pilote.

### A6 — Pas de mounted avec 60 peers + bundle 2 Go

À 60 peers et plusieurs centaines de Mo de bundle, le mode classique ou cascading consomme du réseau pour rien : à chaque cycle, le bundle est physiquement répliqué N fois ou en arbre. Le mounted résout en écrivant une fois sur un partage.

**Symptôme.** Réplication knowledge bundle qui occupe une part visible de la bande passante du datacenter.

**Retrait.** Évaluer mounted avec une équipe storage qui peut engager le NFS en SLA. Si pas possible, rester en cascading et optimiser la taille du bundle (cf. A1, A2).

### A7 — Asymétrie de version SH / peer

Un SH en 9.4.2 et des peers en 9.4.0 fonctionnent en général grâce à la rétrocompatibilité Splunk. Mais des stanzas spécifiques à 9.4.2 dans une app récente peuvent échouer au map sur un peer 9.4.0. La cause est rarement explicite — un peer en erreur sur un index particulier sans message clair.

**Symptôme.** Recherches qui échouent sur un sous-ensemble de peers seulement, sans erreur claire.

**Retrait.** Aligner SH et peers à la même version mineure 9.x. En migration, migrer d'abord les peers (ils tolèrent les bundles 9.x antérieurs) puis les SH.

## 3. Anti-patterns côté CLI / opération

### A8 — Relancer `splunk apply shcluster-bundle` en boucle

Face à un apply qui « semble ne rien faire » (parce que la conf replication interne SHC n'a pas encore propagé), l'admin relance par confort. Effet : chaque relance écrase le précédent dans le pipeline, sans accélérer la propagation effective.

**Symptôme.** Multiples `apply` consécutifs dans l'historique deployer ; `splunkd.log` du captain qui montre des cycles de conf replication interrompus.

**Retrait.** Attendre la fin du cycle, vérifier avec `splunk list shcluster-bundle-status` côté captain. Si la propagation est anormalement lente, investiguer (chap. 05 branche B), ne pas relancer.

### A9 — Confondre `apply cluster-bundle` (CM) et `apply shcluster-bundle` (deployer)

Lancer `splunk apply cluster-bundle` sur le deployer SHC, ou `splunk apply shcluster-bundle` sur le CM, échoue avec un message peu lisible (« command not applicable on this role » ou similaire). L'admin pressé qui tape `apply <tab>` et choisit la mauvaise sous-commande perd du temps en diag.

**Symptôme.** Commande échoue immédiatement, sans push, sans trace de propagation.

**Retrait.** Documenter dans le runbook quel apply se fait sur quel nœud. Au mieux : alias shell sur les nœuds, qui n'expose que la commande pertinente.

### A10 — Tenter `/services/admin/distsearch` ou autre endpoint `/admin/*` non documenté

L'endpoint `/services/admin/distsearch` (et ses cousins `/services/admin/*`) existent en 9.4 et retournent des informations utiles. Splunk demande explicitement de **ne pas** les documenter publiquement ni les automatiser ([RESTprolog](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTprolog) précise la portée des endpoints REST opposables). Les utiliser en script d'investigation ou de monitoring crée une dépendance non opposable : Splunk peut les modifier ou les retirer à tout moment sans changelog.

**Symptôme.** Script qui marchait et qui casse silencieusement après un upgrade mineur.

**Retrait.** Utiliser les endpoints `/services/search/distributed/*` et `/services/shcluster/*` documentés (cf. chap. 06 § 2). Pour les besoins non couverts, ouvrir un demande Splunk pour un endpoint documenté.

## 4. Pièges Splunk inattendus

### P1 — Terminologie `master` → `manager` partiellement migrée

Splunk 9.x a renommé `cluster master` en `cluster manager` côté CM et `slave` en `peer` côté indexer cluster. La migration est partielle :

- Côté **CLI** : `splunk apply cluster-bundle` reste la sous-commande ; pas de `apply manager-bundle`.
- Côté **chemins filesystem** : `etc/manager-apps/` côté CM (9.x), mais `etc/slave-apps/` côté peer (rétrocompatibilité).
- Côté **`splunkd.log`** : `CMMaster`, `CMPeer` encore présents — pas de `CMManager` partout.
- Côté **REST** : `/services/cluster/manager/*` (nouvelle forme) coexiste avec `/services/cluster/master/*` (ancienne forme, redirige). Les deux fonctionnent en 9.4.

**Vivre avec.** Ne pas s'étonner du mélange. Préférer la forme nouvelle dans le code que vous écrivez ; tolérer l'ancienne dans les logs et la doc Splunk historique.

### P2 — Terminologie `slave` → `peer` partiellement migrée

Symétrique de P1. `slave` désigne anciennement un peer indexer cluster. La doc Splunk 9.4 a en majorité migré vers `peer`. Restent des occurrences `slave` :

- `etc/slave-apps/` côté peer (chemin rétrocompatible).
- Certains messages d'erreur ou de log historiques.

**Vivre avec.** Identique à P1. Considérer `slave` ≡ `peer` (indexer) dans tout contexte Splunk post-9.0.

### P3 — Endpoints `/services/admin/*` non documentés

Cf. A10 ci-dessus. Ces endpoints existent, retournent du contenu utile, mais Splunk ne s'engage pas dessus.

**Vivre avec.** Ne pas les utiliser en automatisation. Les utiliser ad hoc, en lecture, dans un debug supervisé, c'est acceptable ; les scripter, non.

### P4 — `allowlist` / `denylist` (9.x) coexistant avec `whitelist` / `blacklist` (legacy)

Splunk 9.4 a achevé la transition vers `allowlist` / `denylist` dans les nouvelles pages de doc et stanzas. Les anciennes formes `whitelist` / `blacklist` restent fonctionnelles dans les `.conf` (alias rétrocompatibles).

**Vivre avec.** Utiliser la forme nouvelle dans les configurations que vous écrivez. Tolérer l'ancienne dans les bases existantes — pas besoin de migrer en masse, c'est cosmétique.

### P5 — Le succès de `splunk apply shcluster-bundle` ne dit rien sur la propagation aux membres

La commande retourne `Successfully applied cluster bundle to captain` dès que le captain a reçu et accepté le bundle. C'est avant la conf replication interne SHC. Un admin qui ne vérifie pas avec `splunk list shcluster-bundle-status` côté captain croit que c'est fait, alors que la propagation aux 2-3 autres membres prend encore 5-30 secondes.

**Vivre avec.** Toujours faire suivre l'apply d'un check `splunk list shcluster-bundle-status` côté captain. Ne pas considérer la propagation comme terminée avant que tous les membres affichent le même `bundle_id`.

### P6 — Restart prédit par `splunk apply` ne se déclenche pas tout seul partout

`splunk apply shcluster-bundle` indique « restart required » dans certains cas mais ne déclenche pas systématiquement le rolling restart. La décision dépend des options (`-push-default-app-conf` augmente la probabilité). L'admin pense que le restart se fera automatiquement et observe le contraire.

**Vivre avec.** Lire la sortie de l'apply. Si « restart required » : déclencher explicitement avec `splunk rolling-restart shcluster-members`.

### P7 — `splunk apply cluster-bundle` peut basculer en force-restart silencieusement

Inversement côté CM : `splunk apply cluster-bundle` peut déclencher un rolling restart des peers sans demande explicite si une stanza modifiée le requiert. L'admin l'apprend en regardant le compteur `count of peers in restart` augmenter.

**Vivre avec.** Toujours précéder l'apply d'un `splunk validate cluster-bundle --check-restart` pour prédire le comportement.

### P8 — Conf replication interne SHC continue, pas synchrone

L'admin qui pense que `splunk apply shcluster-bundle` propage de manière synchrone aux membres se trompe. La propagation est faite par la conf replication interne SHC, qui est continue (cycles courts), pas synchrone. C'est subtil parce que pour de petits bundles à faible cadence, l'effet est imperceptible.

**Vivre avec.** Le délai est `O(conf_replication_period × n)` itérations. Pour un défaut 5 s, prévoir 5-30 s de propagation post-apply, plus si le bundle est gros.

### P9 — Le hash dans `var/run/searchpeers/<…>.bundle` est tronqué

Le hash visible dans le nom de fichier est typiquement tronqué (8-16 caractères, selon version). Ce n'est pas le hash complet du contenu ; c'est une empreinte raccourcie pour le nommage. La comparaison « même hash = même contenu » reste valide en pratique (les collisions sont astronomiquement improbables).

**Vivre avec.** Ne pas tenter de recalculer le hash à partir du contenu pour vérifier — la fonction de hash et le mode de troncature ne sont pas documentés. Se fier au hash tel que rapporté.

### P10 — `splunk help distributed` retourne des sous-commandes selon la version

Les sous-commandes `splunk list distributed-peer` / `splunk show distributed-peers` ont varié entre versions mineures 9.x. La forme exacte de la sous-commande à utiliser se trouve avec `splunk help distributed`. Ne pas supposer qu'une forme vue en 9.4.0 marche en 9.4.2.

**Vivre avec.** Vérifier `splunk help distributed` sur la version courante avant de scripter.

## Récapitulatif

| # | Catégorie | Désignation | Retrait / vivre avec |
| --- | --- | --- | --- |
| A1 | Anti-pattern contenu | Apps trop grosses dans `etc/shcluster/apps/` | Splitter, sortir data, supprimer apps mortes |
| A2 | Anti-pattern contenu | Lookups massives dans bundle | Externaliser en index ou KV Store |
| A3 | Anti-pattern contenu | `.git`, build artifacts dans une app | Nettoyer packaging, blacklist préventive |
| A4 | Anti-pattern contenu | `local/` versionné côté deployer | Convention `default/` only sauf override explicite |
| A5 | Anti-pattern topo | Refuser cascading à 30 peers | Basculer en cascading |
| A6 | Anti-pattern topo | Pas de mounted à 60 peers + bundle 2 Go | Évaluer mounted avec équipe storage |
| A7 | Anti-pattern topo | Asymétrie de version SH / peer | Aligner versions, migrer peers d'abord |
| A8 | Anti-pattern CLI | Relancer `apply shcluster-bundle` en boucle | Attendre, vérifier `list shcluster-bundle-status` |
| A9 | Anti-pattern CLI | Confondre `apply cluster-bundle` et `apply shcluster-bundle` | Runbook explicite, alias shell |
| A10 | Anti-pattern CLI | Endpoints `/services/admin/*` en script | Utiliser endpoints documentés |
| P1 | Piège | Terminologie `master` → `manager` partielle | Tolérer le mélange |
| P2 | Piège | Terminologie `slave` → `peer` partielle | Identifier `slave` ≡ `peer` (indexer) |
| P3 | Piège | Endpoints `/services/admin/*` non documentés | Ad hoc seulement, pas en script |
| P4 | Piège | `allowlist` / `denylist` vs `whitelist` / `blacklist` | Utiliser la forme nouvelle, tolérer l'ancienne |
| P5 | Piège | Succès `apply shcluster-bundle` ≠ propagation effective | Vérifier `list shcluster-bundle-status` |
| P6 | Piège | Restart « required » non déclenché tout seul | Lancer `rolling-restart shcluster-members` |
| P7 | Piège | `apply cluster-bundle` peut restart silencieusement | Précéder par `validate cluster-bundle --check-restart` |
| P8 | Piège | Conf replication interne SHC est continue, pas synchrone | Prévoir délai `O(conf_replication_period × n)` |
| P9 | Piège | Hash dans nom de fichier tronqué | Ne pas recalculer, se fier au rapport Splunk |
| P10 | Piège | Sous-commandes `splunk` varient par version | `splunk help distributed` avant script |

## Quand escalader / quand décider

- **Anti-pattern persistant.** Si un anti-pattern n'est pas retiré malgré l'identification (par exemple A1 sur une app legacy non maintenue), c'est un sujet de gouvernance : décider qui possède l'app, qui paie sa refonte ou son retrait. Pas une décision technique.
- **Piège qui devient bug.** Si un piège se manifeste comme un crash ou une perte de données, ce n'est plus un piège — c'est un bug. Ouvrir un demande Splunk Support avec `splunk diag` du nœud concerné.
- **Décision d'architecture.** Les anti-patterns topologie (A5, A6, A7) sont des décisions d'architecte. Ne pas les retirer en local sans cadrage : un changement de mode de réplication impacte tout le SHC + indexer cluster.

## Sources

- [Splunk DistSearch 9.4 — Cascading knowledge bundle replication](https://docs.splunk.com/Documentation/Splunk/9.4.1/DistSearch/Cascadingknowledgebundlereplication)
- [Splunk DistSearch 9.4 — Mounted knowledge bundle replication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Mountedknowledgebundlereplication)
- [Splunk DistSearch 9.4 — Limit the knowledge bundle size](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Limittheknowledgebundlesize)
- [Splunk Indexer 9.4 — Configuration bundle issues](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Configurationbundleissues)
- [Splunk DistSearch 9.4 — Propagate SHC configuration changes](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/PropagateSHCconfigurationchanges)
- [Splunk REST API 9.4 — Prolog (portée des endpoints opposables)](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTprolog)
- [Splunk Admin 9.4 — distsearch.conf (`replicationAllowlist`, `replicationBlacklist`)](https://docs.splunk.com/Documentation/Splunk/9.4.0/Admin/Distsearchconf)
