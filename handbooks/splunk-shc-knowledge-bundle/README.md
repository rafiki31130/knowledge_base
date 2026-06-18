# Splunk SHC Knowledge Bundle Handbook

> Un manuel court pour l'administrateur ou l'architecte Splunk Enterprise on-prem qui sait poser un Search Head Cluster et un indexer cluster, mais qui bute sur le comportement réel des *knowledge bundles* en environnement distribué. Trois mécanismes Splunk différents portent le mot « bundle » : ce handbook les sépare, en décrit la mécanique de propagation, fournit l'arbre de diagnostic des incidents les plus fréquents, et consolide la boîte à outils CLI / REST / logs / SPL d'investigation.

## What this handbook is and isn't

**Is.** Un livre de plomberie : la mécanique réelle de propagation des configurations dans un Search Head Cluster (SHC) doublé d'un indexer cluster. Il sépare d'entrée trois mécanismes que la doc Splunk confond sous le mot « bundle » — *configuration bundle SHC* (deployer → membres), *knowledge bundle de search* (search head → search peers), *configuration bundle indexer cluster* (cluster manager → peers) — et leur consacre un chapitre dédié. Il consolide ensuite l'arbre de diagnostic des incidents les plus fréquents et la boîte à outils d'investigation (CLI, REST, filtres `splunkd.log`, SPL `index=_internal`).

**Isn't.** Un tutoriel de pose de SHC. Un manuel d'installation. Une introduction à Splunk. Un guide Splunk Cloud (où le deployer est caché et la mécanique d'ops change). Un manuel SmartStore — SmartStore modifie la mécanique de buckets, pas celle du bundle ; il est cité en pointeur, jamais détaillé. Le deployment server pour forwarders est explicitement hors scope ; il est couvert ailleurs dans la KB (`splunk/concepts/deployment-server.md`).

## Persona

Vous administrez ou architecturez un Splunk Enterprise 9.x on-prem. Vous savez monter un Search Head Cluster, vous distinguez un *captain* d'un *member*, vous lisez un `server.conf` sans hésiter, vous comprenez ce qu'est `_internal` et vous savez ouvrir un `splunkd.log` à la bonne heure. Vous avez déjà passé une demi-journée à essayer de comprendre pourquoi `splunk apply shcluster-bundle` ne semble rien faire — ou pourquoi une recherche reste bloquée « en attente du bundle » sur un seul peer. Vous voulez une référence opposable et une checklist d'investigation, pas un cours.

Vous n'êtes **pas** la cible si vous débutez sur Splunk, si vous êtes un analyste SPL sans accès admin (cf. le `splunk-user-handbook` de la même KB), si vous travaillez sur Splunk Cloud (modèle ops trop différent), ou si vous cherchez la procédure d'installation d'un SHC.

## Scope

- **Splunk Enterprise 9.x on-prem**, exemples figés sur **9.4**.
- **SHC + indexer cluster** ensemble — c'est l'archétype où la confusion bundle naît. Un SHC seul ou un indexer cluster seul reste lisible avec ce handbook, mais les deux ensemble en motivent l'écriture.
- Couvre les **trois mécanismes** appelés « bundle » dans le quotidien d'un admin : configuration bundle SHC, knowledge bundle de search distribuée, configuration bundle indexer cluster. Le titre met l'accent sur le knowledge bundle (le plus subtil), mais le chapitre 00 cadre les trois.
- Couvre les **trois topologies** de réplication knowledge bundle SH → peers : *classic*, *cascading*, *mounted*.
- Couvre les incidents **observables** (recherche bloquée, bundle trop gros, peer hors-cluster, hash divergent, restart non déclenché) et fournit l'arbre de diagnostic associé.

### Hors scope

- **Splunk Cloud** — deployer caché, modèle ops différent.
- **SmartStore** — pointé en chap. 03, pas détaillé. Change la mécanique de buckets, pas celle du bundle.
- **Deployment server pour forwarders** — déjà couvert dans la KB (`splunk/concepts/deployment-server.md`).
- **SOAR, Observability, Enterprise Security, ITSI**.
- **Splunk 9.0 antérieur** et **10.x** — projet de mise à jour quand 10.x sera dominant.

## How to use this handbook

Les chapitres sont conçus pour être lus indépendamment, mais l'ordre proposé est pédagogique : chapitre 00 pose le lexique opposable utilisé partout dans le livre, chapitres 01 → 04 décrivent la mécanique de chaque mécanisme dans l'ordre où un admin les rencontre, chapitre 05 fournit l'arbre de diagnostic à entrer par symptôme, chapitre 06 est la **boîte à outils** (CLI, REST, logs, SPL) qu'on rouvre face à un incident, chapitre 07 consolide les anti-patterns à bannir, chapitre 99 est la cheatsheet imprimable.

Face à un incident, l'entrée est toujours la même : chapitre 05 (arbre de diagnostic) pour caractériser le symptôme, chapitre 06 (investigations) pour les commandes précises, chapitre 99 (cheatsheet) si vous savez déjà à peu près où vous allez.

## Table of contents

| # | Chapitre | Objet |
| --- | --- | --- |
| 00 | [Foundations — trois bundles, un seul mot](./00-foundations.md) | Lexique opposable, mécaniques distinctes, propriétaires |
| 01 | [Constitution du configuration bundle SHC côté deployer](./01-bundle-shc-constitution.md) | `etc/shcluster/apps`, `splunk apply shcluster-bundle`, conf replication interne |
| 02 | [Constitution du knowledge bundle côté search head](./02-bundle-search-constitution.md) | Consolidation, hash, delta vs full, `distsearch.conf` |
| 03 | [Réplication vers les search peers](./03-replication-vers-peers.md) | Classic, cascading, mounted ; `var/run/searchpeers/` ; échecs partiels |
| 04 | [Séquence d'une recherche distribuée](./04-sequence-recherche-distribuee.md) | bundle ready → fan-out → map → reduce |
| 05 | [Troubleshooting — arbre de diagnostic](./05-troubleshooting-arbre-de-diag.md) | Symptôme → hypothèses → action → critère d'escalade |
| 06 | [Investigations — boîte à outils](./06-investigations.md) | CLI, REST, filtres `splunkd.log`, SPL `index=_internal` |
| 07 | [Pièges et anti-patterns](./07-pieges-anti-patterns.md) | Contenu, topologie, CLI, terminologie 9.x |
| 99 | [Cheatsheet diag rapide](./99-cheatsheet-diag-rapide.md) | Une page imprimable |

## Conventions

### Substituts d'anonymisation

Étend la table canonique du `handbooks/README.md` de la KB avec les noms propres à l'écosystème SHC + indexer cluster utilisés tout au long du handbook.

| Catégorie | Valeur canonique |
| --- | --- |
| Hostnames génériques (hérités) | `host01`, `web01`, `db01` |
| Search peers (indexers) | `peer01`, `peer02`, `peer03` |
| Search head cluster members | `shcMember01`, `shcMember02`, `shcMember03` |
| Captain (rôle, peut tourner sur n'importe quel membre) | `captain01` |
| Deployer SHC | `deployer01` |
| Cluster manager (indexer cluster, terminologie 9.x) | `cm01` |
| Standalone search head (hors SHC, pour contre-exemple) | `sh01` |
| Forwarders | `uf01`, `hf01` |
| Domaine | `example.com`, `corp.example.com` |
| IP / CIDR | `10.0.0.0/24`, `192.0.2.0/24` (RFC 5737), `2001:db8::/32` |
| Utilisateurs | `alice`, `bob`, `svc_app` |
| Apps internes | `my_company_app`, `soc_app` |
| Indexes | `main`, `security`, `os`, `network`, `summary_app01` |
| GUID SHC member (forme) | `00000000-0000-0000-0000-000000000001` à `…003` |
| Chemins | `$SPLUNK_HOME/etc/shcluster/apps/`, `$SPLUNK_HOME/var/run/searchpeers/<sh_guid>-<epoch>-<hash>.bundle` |

Toute valeur réelle (hostname, IP, GUID, hash, timestamp) est interdite. Le handbook est publié sur un repo GitHub public ; voir `CONTRIBUTING.md` de la KB pour le détail de la règle R7.

### Notation des commandes

- **CLI Splunk** : fence `` ```bash ``, une commande par ligne, préfixée `splunk` (jamais `./splunk`, jamais de chemin absolu). Options longues sur leur propre ligne avec `\`.
- **REST API** : fence `` ```bash ``, forme `curl -k -u admin:<password> https://<host>:8089/services/...`. Le placeholder `<password>` ne porte jamais de valeur réelle. Méthode HTTP explicitée (`-X GET`, `-X POST`), paramètres en `-d`. Port mgmt = `8089`, port replication SHC = `8090` (à vérifier sur `server.conf` `[shclustering] mgmt_uri` du membre cible).
- **Extraits de `splunkd.log`** : fence `` ```text ``, 1 à 3 lignes maximum par exemple, anonymisés (timestamp `YYYY-MM-DD HH:MM:SS.sss`, GUID canonique `00000000-0000-0000-0000-000000000001`, hash placeholder `aaaaaaaa…`).
- **SPL** : fence `` ```spl ``, time range toujours explicite, un pipe par ligne quand le pipeline dépasse 80 colonnes.
- **`.conf`** : fence `` ```ini `` avec la stanza `[…]` englobante, jamais un extrait sans stanza.

### Terminologie 9.4

Splunk 9.4 a achevé sa transition terminologique de `master` → `manager` (cluster manager) et de `slave` → `peer` (search peer). Les logs et certains endpoints REST conservent l'ancienne forme. Quand le handbook cite un terme legacy (par exemple `CMMaster` dans `splunkd.log`), il l'explicite. À noter aussi : Splunk 9.4 emploie `allowlist` / `denylist` (forme actuelle) tout en gardant `whitelist` / `blacklist` comme alias rétrocompatibles ; le handbook utilise la forme actuelle et signale l'alias à la première occurrence (chap. 02).

### Citation des sources

Chaque affirmation factuelle pointe inline vers la documentation Splunk officielle 9.4 (`docs.splunk.com/Documentation/Splunk/9.4.x/...`) ou vers le Splexicon. Le Splexicon est cité pour les définitions seules, jamais pour décrire un comportement. Lantern et le blog Splunk sont acceptés comme contexte mais jamais comme norme isolée. Chaque chapitre se termine par une section `## Sources` qui consolide ses citations.

## Global sources

### Distributed Search Manual 9.4

- [Knowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Knowledgebundlereplication)
- [Whatsearchheadssend](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Whatsearchheadssend)
- [Classicknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.1/DistSearch/Classicknowledgebundlereplication)
- [Cascadingknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.1/DistSearch/Cascadingknowledgebundlereplication)
- [Mountedknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Mountedknowledgebundlereplication)
- [Limittheknowledgebundlesize](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Limittheknowledgebundlesize)
- [Troubleshootknowledgebundlereplication](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Troubleshootknowledgebundlereplication)
- [Configuredistributedsearch](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/Configuredistributedsearch)
- [SHCarchitecture](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/SHCarchitecture)
- [PropagateSHCconfigurationchanges](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/PropagateSHCconfigurationchanges)
- [SHCdeploymentoverview](https://docs.splunk.com/Documentation/Splunk/9.4.0/DistSearch/SHCdeploymentoverview)
- [ViewSHCstatus](https://docs.splunk.com/Documentation/Splunk/9.4.2/DistSearch/ViewSHCstatus)
- [HowconfrepoworksinSHC](https://docs.splunk.com/Documentation/Splunk/9.4.1/DistSearch/HowconfrepoworksinSHC)

### Admin / Conf references 9.4

- [Distsearchconf](https://docs.splunk.com/Documentation/Splunk/9.4.0/Admin/Distsearchconf)
- [Serverconf](https://docs.splunk.com/Documentation/Splunk/9.4.2/Admin/Serverconf)

### Indexer Cluster 9.4

- [Updatepeerconfigurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Updatepeerconfigurations)
- [Managecommonconfigurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Managecommonconfigurations)
- [Configurationbundleissues](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Configurationbundleissues)
- [Managesinglepeerconfigurations](https://docs.splunk.com/Documentation/Splunk/9.4.0/Indexer/Managesinglepeerconfigurations)
- [Restartthecluster](https://docs.splunk.com/Documentation/Splunk/9.4.2/Indexer/Restartthecluster)
- [Configuremanagerwithserverconf](https://docs.splunk.com/Documentation/Splunk/9.4.1/Indexer/Configuremanagerwithserverconf)

### REST API Reference 9.4

- [RESTprolog](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTprolog)
- [RESTcluster](https://docs.splunk.com/Documentation/Splunk/9.4.0/RESTREF/RESTcluster)

### Troubleshooting 9.4

- [WhatSplunklogsaboutitself](https://docs.splunk.com/Documentation/Splunk/9.4.2/Troubleshooting/WhatSplunklogsaboutitself)

### Splexicon (définitions uniquement)

- [Knowledgebundle](https://docs.splunk.com/Splexicon:Knowledgebundle)
- [Configurationbundle](https://docs.splunk.com/Splexicon:Configurationbundle)
- [Searchpeerreplication](https://docs.splunk.com/Splexicon:Searchpeerreplication)
- [Searchpeer](https://docs.splunk.com/Splexicon:Searchpeer)
- [Searchheadcluster](https://docs.splunk.com/Splexicon:Searchheadcluster)
- [Deployer](https://docs.splunk.com/Splexicon:Deployer)
- [Clustercaptain](https://docs.splunk.com/Splexicon:Clustercaptain)
- [Managernode](https://docs.splunk.com/Splexicon:Managernode)

## Versioning note

Le handbook est écrit contre **Splunk Enterprise 9.x on-prem**, exemples figés sur **9.4**. Splunk Cloud, SmartStore, Splunk 9.0 antérieur et Splunk 10.x sont explicitement hors scope.

Trois précisions de versioning à connaître avant de lire :

1. **Terminologie `allowlist` / `denylist`** : 9.4 utilise les deux formes. Le handbook utilise la forme actuelle (`allowlist`, `denylist`) et signale les alias rétrocompatibles `whitelist` / `blacklist` à leur première occurrence (chap. 02).
2. **Endpoint `/services/admin/distsearch`** : endpoint admin non documenté publiquement par Splunk. Tentation à éviter — il existe en 9.4 mais n'a pas vocation à être appelé hors support. Le handbook ne le liste pas comme outil ; il est traité en chap. 07 comme un piège (« endpoint admin non opposable »).
3. **Composants `splunkd.log`** : Splunk ne documente individuellement, parmi les composants pertinents pour le bundle, que `DistributedBundleReplicationManager`. Les autres (`BundleReplicator`, `ConfReplication*`, `CMMaster`, `CMPeer`, `ApplyBundleHandler`) sont **observés empiriquement** dans `splunkd.log` 9.4 sans page de référence dédiée. Le chap. 06 le matérialise explicitement par une colonne « Source / statut ».

Quand une version mineure 9.x diverge sur un comportement (par exemple un changement de chemin de bundle entre 9.4.0 et 9.4.2), le chapitre concerné le signale inline.
