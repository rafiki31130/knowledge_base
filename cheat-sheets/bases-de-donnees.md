---
title: Bases de données (CouchDB & MongoDB)
category: cheat-sheets
tags: [bases-de-donnees, couchdb, mongodb, nosql, curl, mongosh, cheat-sheet]
created: 2026-06-08
---

# Bases de données (CouchDB & MongoDB) — Cheat-sheet

## À quoi ça sert

Administrer au quotidien deux bases NoSQL documentaires. **CouchDB** se pilote
entièrement par son API HTTP (donc avec `curl` ou l'interface web Fauxton) :
inspection des bases, compaction, statistiques, réplication. **MongoDB** se pilote
avec le shell `mongosh` et les outils `mongodump`/`mongorestore`. On y touche pour
vérifier l'état d'une base, lancer une maintenance ou faire une sauvegarde.

## Commandes de base

### CouchDB — via HTTP (`curl`)

```bash
# Variables pratiques (auth basique ; les identifiants restent des placeholders)
HOST="http://example.com:5984"
AUTH="-u admin:<motdepasse>"              # ou via fichier ~/.netrc pour ne pas l'exposer

curl $AUTH "$HOST/_up"                     # état du nœud (doit répondre {"status":"ok"})
curl $AUTH "$HOST/_all_dbs"                # lister toutes les bases
curl $AUTH "$HOST/<db>"                    # métadonnées d'une base (doc_count, taille...)
curl $AUTH "$HOST/_membership"             # nœuds du cluster
```

```bash
# Statistiques et maintenance
curl $AUTH "$HOST/_node/_local/_stats"     # statistiques du nœud (requêtes, latence...)
curl $AUTH "$HOST/<db>/_compact" -X POST -H "Content-Type: application/json"
                                           # compacter une base (récupère l'espace)
```

```bash
# Réplication ponctuelle entre deux bases (one-shot)
curl $AUTH "$HOST/_replicate" -X POST -H "Content-Type: application/json" -d '{
  "source": "http://example.com:5984/<db>",
  "target": "http://example.com:5984/<db_cible>"
}'
# Ajouter "create_target": true pour créer la base cible si absente,
# et "continuous": true pour une réplication continue.
```

Fauxton : interface web d'administration livrée avec CouchDB, accessible sur
`http://example.com:5984/_utils/` (mêmes opérations que ci-dessus, en clic).

### MongoDB — shell `mongosh`

```bash
mongosh                                    # connexion locale par défaut (localhost:27017)
mongosh "mongodb://user01@example.com:27017/<db>"   # URI de connexion (demande le mot de passe)
mongosh --eval 'db.adminCommand("ping")'   # commande unique sans entrer dans le shell
```

```javascript
// Une fois dans mongosh :
show dbs                                   // lister les bases
use <db>                                   // sélectionner une base (la crée à la 1re écriture)
show collections                           // lister les collections de la base courante
db.stats()                                 // statistiques de la base (taille, objets...)

db.<coll>.countDocuments()                 // nombre de documents d'une collection
db.<coll>.find()                           // tous les documents (premiers résultats)
db.<coll>.find({ champ: "valeur" })        // filtrer
db.<coll>.find().limit(5).pretty()         // limiter et formater
db.<coll>.findOne()                        // un seul document
```

```bash
# Sauvegarde / restauration (depuis le shell système, pas mongosh)
mongodump --uri="mongodb://user01@example.com:27017" --out=/sauvegarde/
mongodump --db=<db> --collection=<coll> --out=/sauvegarde/   # cibler une base/collection

mongorestore /sauvegarde/                  # restaurer une arborescence de dump
mongorestore --db=<db> /sauvegarde/<db>/   # restaurer une base précise
mongorestore --drop /sauvegarde/           # vider avant restauration (écrase l'existant)
```

## Pièges fréquents

- **CouchDB : oublier `Content-Type: application/json` sur un POST** : une requête de
  réplication ou de compaction sans cet en-tête est mal interprétée et renvoie une
  erreur 400/415 peu explicite.
- **CouchDB : compaction = espace disque temporaire** : la compaction réécrit le
  fichier de base ; prévoir l'espace libre équivalent à la base avant de lancer.
- **CouchDB : identifiants dans l'URL** : `http://admin:motdepasse@host` expose le
  secret dans l'historique et les logs proxy. Préférer `-u` ou `~/.netrc`.
- **MongoDB : `find()` n'affiche qu'un lot** : le shell pagine (`it` pour la suite).
  Pour un comptage fiable, utiliser `countDocuments()`, pas la longueur d'un affichage.
- **MongoDB : `mongorestore --drop` écrase** : il supprime chaque collection avant de
  la réimporter. Sans sauvegarde fraîche, une restauration ratée est irréversible.
- **MongoDB : `use <db>` ne crée rien immédiatement** : une base ou collection
  n'existe réellement qu'après la première écriture. Un `show dbs` peut donc ne pas
  lister une base « sélectionnée » mais vide.
- **`mongo` (ancien shell) vs `mongosh`** : l'ancien client `mongo` est déprécié ;
  `mongosh` est le shell actuel et a une syntaxe légèrement différente.

## Voir aussi

- [Docker](./docker.md) — ces bases tournent souvent en conteneur
- [Linux & systemd](./linux-systemd.md) — gérer le service `couchdb`/`mongod`, lire ses logs
- [Stockage & NAS](./stockage-nas.md) — où déposer les sauvegardes `mongodump`/dumps
