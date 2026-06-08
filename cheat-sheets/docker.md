---
title: Docker
category: cheat-sheets
tags: [docker, conteneurs, compose, cheat-sheet]
created: 2026-06-08
---

# Docker — Cheat-sheet

## À quoi ça sert

Docker exécute des applications dans des conteneurs isolés à partir d'images.
On y touche au quotidien pour voir ce qui tourne, lire des logs, entrer dans un
conteneur, inspecter sa configuration, et — avec Docker Compose — gérer une pile
multi-services déclarée dans un `compose.yaml`. Les commandes ci-dessous couvrent
l'exploitation courante, pas la construction d'images.

## Commandes de base

### Conteneurs (`docker`)

```bash
docker ps                            # conteneurs en cours d'exécution
docker ps -a                         # tous, y compris arrêtés
docker logs <container>              # logs d'un conteneur
docker logs -f <container>           # suivre les logs en continu (follow)
docker logs --tail 100 <container>   # 100 dernières lignes
docker logs --since 10m <container>  # depuis 10 minutes
```

```bash
docker exec -it <container> sh       # shell interactif dans le conteneur (ou bash)
docker exec <container> <commande>   # exécuter une commande ponctuelle
docker inspect <container>           # config complète au format JSON
docker inspect -f '{{.State.Status}}' <container>   # extraire un champ précis
docker stats                         # CPU/RAM/IO en temps réel (tous les conteneurs)
docker stats --no-stream             # instantané unique (non interactif)
```

```bash
docker start <container>             # démarrer un conteneur arrêté
docker stop <container>              # arrêt propre (SIGTERM puis SIGKILL)
docker restart <container>           # redémarrer
docker rm <container>                # supprimer un conteneur arrêté
docker rm -f <container>             # forcer la suppression (l'arrête d'abord)
```

### Images, volumes, réseaux

```bash
docker images                        # lister les images locales
docker pull <image>:<tag>            # télécharger une image
docker rmi <image>                   # supprimer une image

docker volume ls                     # lister les volumes
docker volume inspect <volume>       # détails d'un volume (point de montage)

docker network ls                    # lister les réseaux
docker network inspect <network>     # détails (conteneurs connectés, sous-réseau)
```

### Docker Compose (`docker compose`)

```bash
# À lancer dans le dossier contenant compose.yaml (ou via -f <fichier>)
docker compose up -d                 # démarrer la pile en arrière-plan (detached)
docker compose down                  # arrêter et supprimer conteneurs + réseaux
docker compose down -v               # idem + supprimer les volumes nommés (destructif)
docker compose ps                    # état des services de la pile
docker compose logs -f               # suivre les logs de tous les services
docker compose logs -f <service>     # suivre un seul service
docker compose pull                  # mettre à jour les images de la pile
docker compose restart <service>     # redémarrer un service
docker compose exec <service> sh     # shell dans le conteneur d'un service
docker compose up -d --force-recreate <service>   # recréer après changement de conf
```

### Nettoyage

```bash
docker system df                     # espace disque utilisé (images, conteneurs, volumes)
docker system prune                  # supprimer conteneurs arrêtés, réseaux/images orphelins
docker system prune -a               # + toutes les images non utilisées (agressif)
docker system prune --volumes        # inclure les volumes non utilisés (destructif)
docker image prune                   # uniquement les images « dangling »
```

## Pièges fréquents

- **`docker compose down` supprime, ne suspend pas** : il détruit conteneurs et réseaux.
  Pour juste arrêter sans supprimer, utiliser `docker compose stop`.
- **`down -v` / `prune --volumes` = perte de données** : les volumes contiennent les
  données persistantes (bases, configs). Ne jamais les supprimer sans sauvegarde.
- **Logs qui gonflent le disque** : sans limite de log (`max-size`/`max-file`), un
  conteneur bavard peut saturer `/var/lib/docker`. Surveiller avec `docker system df`.
- **`docker-compose` (tiret) vs `docker compose` (plugin v2)** : l'ancien binaire à tiret
  est déprécié ; préférer `docker compose`. Les options diffèrent légèrement.
- **`exec sh` qui échoue** : les images minimalistes (Alpine) n'ont pas `bash` ; utiliser
  `sh`. Les images « distroless » n'ont parfois aucun shell.
- **Éditer un fichier dans le conteneur** : les changements sont perdus au prochain
  `up --force-recreate` / `pull`. Persister via un volume ou rebuild de l'image.
- **`prune` sans filtre en prod** : `prune -a` retire les images non *actuellement*
  utilisées, y compris celles dont on aura besoin pour un rollback rapide.

## Voir aussi

- [Proxmox VE](./proxmox.md) — conteneurs LXC vs conteneurs Docker
- [HAProxy & TLS](./haproxy-tls.md) — exposer des conteneurs derrière un reverse-proxy
- [Linux & systemd](./linux-systemd.md) — gérer le démon Docker et les services hôte
