---
title: Linux & systemd
category: cheat-sheets
tags: [linux, systemd, journalctl, administration, cheat-sheet]
created: 2026-06-08
---

# Linux & systemd — Cheat-sheet

## À quoi ça sert

systemd gère les services (units) et les logs (journal) sur la plupart des
distributions Linux modernes. Cette fiche regroupe les commandes d'exploitation
courantes : piloter un service, lire ses logs, et le minimum vital de diagnostic
système (disque, mémoire, processus, réseau, fichiers) plus la gestion de paquets
sur les distributions à base Debian/Ubuntu (`apt`).

## Commandes de base

### Services — `systemctl`

```bash
systemctl status <service>           # état détaillé + dernières lignes de log
systemctl start <service>            # démarrer
systemctl stop <service>             # arrêter
systemctl restart <service>          # redémarrer
systemctl reload <service>           # recharger la conf sans coupure (si supporté)
systemctl enable <service>           # activer au démarrage
systemctl disable <service>          # désactiver au démarrage
systemctl enable --now <service>     # activer ET démarrer immédiatement
systemctl is-active <service>        # actif ? (sortie scriptable)
systemctl is-enabled <service>       # activé au boot ?
```

```bash
systemctl list-units --type=service              # services chargés
systemctl list-units --failed                    # units en échec (diagnostic rapide)
systemctl list-unit-files --state=enabled        # ce qui démarre au boot
systemctl daemon-reload                          # recharger après édition d'un .service
systemctl cat <service>                          # voir le fichier unit effectif
```

### Logs — `journalctl`

```bash
journalctl -u <service>              # logs d'un service
journalctl -u <service> -f          # suivre en continu (follow)
journalctl -u <service> -e          # sauter à la fin
journalctl -u <service> --since "1 hour ago"     # depuis 1 h
journalctl -u <service> --since today             # depuis aujourd'hui
journalctl -u <service> --since "2026-01-01 08:00" --until "2026-01-01 09:00"
journalctl -u <service> -p err      # seulement priorité error et au-dessus
journalctl -b                       # logs depuis le dernier démarrage
journalctl -k                       # messages du noyau (kernel)
journalctl --disk-usage             # espace occupé par le journal
journalctl --vacuum-time=7d         # purger les logs de plus de 7 jours
```

### Diagnostic système

```bash
df -h                                # espace disque par système de fichiers (lisible)
df -i                                # inodes (utile si « no space » alors que df -h est OK)
du -sh <chemin>                      # taille totale d'un dossier
du -sh * | sort -h                   # taille de chaque entrée, triée croissant
free -h                             # mémoire et swap (lisible)
top                                  # processus en temps réel (interactif)
htop                                 # variante ergonomique (si installé)
uptime                               # charge système (load average)
```

```bash
ps aux                               # tous les processus (instantané)
ps aux --sort=-%mem | head          # plus gros consommateurs de mémoire
ps -ef | grep <motif>               # rechercher un processus
ss -tlnp                             # ports TCP en écoute + processus
kill <pid>                           # SIGTERM (arrêt propre)
kill -9 <pid>                        # SIGKILL (forcé, dernier recours)
```

```bash
find /chemin -name "*.log"           # chercher par nom
find /chemin -type f -mtime +7       # fichiers modifiés il y a plus de 7 jours
find /chemin -type f -size +100M     # fichiers de plus de 100 Mo
find /chemin -name "*.tmp" -delete   # trouver et supprimer (vérifier d'abord sans -delete)
```

### Gestion de paquets — `apt` (Debian/Ubuntu)

```bash
apt update                           # rafraîchir l'index des paquets
apt upgrade                          # mettre à jour les paquets installés
apt full-upgrade                     # mises à jour pouvant ajouter/retirer des paquets
apt install <paquet>                 # installer
apt remove <paquet>                  # désinstaller (garde la config)
apt purge <paquet>                   # désinstaller + config
apt autoremove                       # retirer les dépendances devenues inutiles
apt search <motif>                   # chercher un paquet
apt show <paquet>                    # détails d'un paquet
apt list --installed                 # paquets installés
```

## Pièges fréquents

- **Oublier `daemon-reload`** : après avoir édité un fichier `.service`, systemd lit
  l'ancienne version tant qu'on n'a pas lancé `systemctl daemon-reload`.
- **`enable` ≠ `start`** : `enable` configure le démarrage au boot mais ne lance pas le
  service maintenant. Utiliser `enable --now` pour les deux d'un coup.
- **« No space left » mais `df -h` semble OK** : souvent une saturation d'inodes (`df -i`)
  ou un fichier supprimé encore ouvert par un processus (`lsof | grep deleted`).
- **`kill -9` par réflexe** : SIGKILL ne laisse pas le processus nettoyer (fichiers temp,
  verrous, données en mémoire). Tenter `kill` (SIGTERM) d'abord.
- **Journal qui remplit le disque** : sans limite, `/var/log/journal` grossit. Plafonner
  via `SystemMaxUse` dans `journald.conf` ou purger avec `--vacuum-time`.
- **`apt upgrade` qui ne met pas tout à jour** : `upgrade` n'ajoute/retire pas de paquets ;
  certaines mises à jour de noyau exigent `apt full-upgrade`.
- **`find ... -delete` non vérifié** : toujours lancer la commande sans `-delete` d'abord
  pour relire la liste avant de supprimer.

## Voir aussi

- [Docker](./docker.md) — le démon Docker est lui-même un service systemd
- [HAProxy & TLS](./haproxy-tls.md) — exemple de service géré par systemctl/journalctl
- [Réseau & pfSense](./reseau-pfsense.md) — diagnostic réseau complémentaire
- [Proxmox VE](./proxmox.md) — administrer une VM/CT depuis l'intérieur
