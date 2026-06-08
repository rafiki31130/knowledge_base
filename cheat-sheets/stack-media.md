---
title: Stack média conteneurisée
category: cheat-sheets
tags: [docker, media, arr, qbittorrent, gluetun, vpn, cheat-sheet]
created: 2026-06-08
---

# Stack média conteneurisée — Cheat-sheet

## À quoi ça sert

Une « stack média » regroupe des services conteneurisés qui automatisent la gestion d'une
médiathèque : applications *arr (gestion/recherche), un client de téléchargement
(`qbittorrent-nox`), parfois un conteneur VPN (gluetun) qui sert de passerelle réseau, et
un serveur de lecture. Cette fiche couvre les **patterns d'exploitation** : exécution
Docker/Compose, API des services, port-forwarding via le conteneur VPN, et healthchecks.

Les commandes Docker/Compose génériques ne sont pas reprises ici → voir
[Docker](./docker.md). Placeholders : `<container>`, `example.com`, `$API_KEY`.

## Commandes de base

### Pilotage via Docker / Compose

```bash
# Exploitation courante (détails et options → docker.md)
docker compose up -d                 # démarrer la pile en arrière-plan
docker compose ps                    # état des services
docker compose logs -f <container>   # suivre les logs d'un service
docker compose restart <container>   # redémarrer un service
docker compose pull && docker compose up -d   # mettre à jour les images
```

### Client de téléchargement — `qbittorrent-nox`

`qbittorrent-nox` est la version sans interface graphique, pilotable par sa WebUI/API.

```bash
# Dans l'image, le service écoute sur le port de la WebUI (8080 par défaut).
# Diagnostic via les logs du conteneur :
docker compose logs -f <container>   # ex : mots de passe temporaires au 1er démarrage

# API WebUI : on s'authentifie d'abord (cookie de session), puis on appelle les endpoints
# 1. Login (récupère un cookie de session dans cookies.txt)
curl -s -c cookies.txt \
     --data "username=<user>&password=$WEBUI_PASSWORD" \
     "http://example.com:8080/api/v2/auth/login"

# 2. Lister les torrents (réutilise le cookie)
curl -s -b cookies.txt \
     "http://example.com:8080/api/v2/torrents/info"

# 3. Version de l'application
curl -s -b cookies.txt "http://example.com:8080/api/v2/app/version"
```

### API des applications *arr — en-tête `X-Api-Key`

Les applications *arr exposent une API REST authentifiée par une clé d'API (visible dans
leurs réglages, à garder en `$API_KEY`). Schéma commun (le chemin de version peut varier
selon l'application) :

```bash
# État système de l'application
curl -s -H "X-Api-Key: $API_KEY" \
     "http://example.com:<port>/api/v3/system/status"

# File d'attente / activité
curl -s -H "X-Api-Key: $API_KEY" \
     "http://example.com:<port>/api/v3/queue"

# Vérifier la santé (warnings de configuration remontés par l'app)
curl -s -H "X-Api-Key: $API_KEY" \
     "http://example.com:<port>/api/v3/health"

# La clé peut aussi passer en querystring (équivalent, moins propre)
curl -s "http://example.com:<port>/api/v3/system/status?apikey=$API_KEY"
```

### Passerelle VPN (gluetun) et port-forwarding

Pattern courant : le client de téléchargement utilise le **réseau du conteneur VPN**
(`network_mode: "service:<gluetun>"`), de sorte que tout son trafic sort par le VPN. Les
ports de la WebUI doivent alors être publiés **sur le conteneur gluetun**, pas sur le
client.

```yaml
# Extrait compose (générique) — le client partage la pile réseau du VPN
services:
  <gluetun>:
    image: <image-gluetun>
    cap_add: ["NET_ADMIN"]
    ports:
      - "8080:8080"          # WebUI du client, publiée VIA gluetun
    environment:
      VPN_SERVICE_PROVIDER: "<provider>"
      # secrets du VPN -> variables d'environnement, jamais en clair ici

  <container>:               # client de téléchargement
    image: <image-client>
    network_mode: "service:<gluetun>"   # pas de "ports:" propre : tout passe par gluetun
    depends_on: ["<gluetun>"]
```

```bash
# Vérifier l'IP de sortie réellement utilisée (doit être celle du VPN, pas la tienne)
docker compose exec <gluetun> wget -qO- "https://ifconfig.me"
# Récupérer un port forwardé annoncé par gluetun (si le provider le supporte)
docker compose exec <gluetun> cat /tmp/gluetun/forwarded_port 2>/dev/null
```

### Healthchecks

```yaml
# Healthcheck déclaré dans compose : marque le conteneur healthy/unhealthy
services:
  <container>:
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:<port>/ping"]
      interval: 30s
      timeout: 10s
      retries: 3
```

```bash
docker compose ps                    # colonne STATUS : (healthy) / (unhealthy)
docker inspect -f '{{.State.Health.Status}}' <container>   # état de santé brut
```

## Pièges fréquents

- **Fuite d'IP si le VPN tombe** : avec `network_mode: "service:<gluetun>"`, si gluetun
  redémarre/plante, le client peut perdre toute connectivité (kill-switch) — c'est voulu.
  Mais une mauvaise config peut router hors VPN : toujours vérifier l'IP de sortie.
- **Ports publiés au mauvais endroit** : quand un service partage le réseau de gluetun, sa
  directive `ports:` doit être sur **gluetun**, pas sur le service. Sinon Docker refuse ou
  le port n'est pas joignable.
- **`X-Api-Key` vs clé en querystring** : préférer l'en-tête ; la clé en URL apparaît dans
  les logs d'accès et l'historique. Ne jamais committer `$API_KEY`.
- **Chemin de version d'API** : `/api/v3` n'est pas universel selon l'application *arr ;
  vérifier la version exposée avant d'automatiser.
- **Mot de passe temporaire qBittorrent** : aux premiers démarrages, un mot de passe WebUI
  est généré et affiché **dans les logs du conteneur** ; le récupérer via `logs`, puis le
  changer.
- **Permissions des volumes (PUID/PGID)** : un conteneur média qui n'écrit pas dans son
  volume vient presque toujours d'un mauvais mapping d'UID/GID — pas d'un bug applicatif.
- **`pull` puis oubli de `up -d`** : `docker compose pull` télécharge l'image mais ne
  recrée pas le conteneur. Enchaîner `up -d` pour appliquer la nouvelle image.

## Voir aussi

- [Docker](./docker.md) — exploitation Docker/Compose de base (logs, volumes, nettoyage, recreate).
- [Réseau & pfSense](./reseau-pfsense.md) — routage, VPN et port-forwarding côté réseau.
- [Secrets & SSH](./secrets-ssh.md) — garder `$API_KEY` et les identifiants VPN hors des fichiers versionnés.
