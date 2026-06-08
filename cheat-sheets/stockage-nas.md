---
title: Stockage & NAS
category: cheat-sheets
tags: [stockage, nas, samba, cifs, nfs, fstab, backup, cheat-sheet]
created: 2026-06-08
---

# Stockage & NAS — Cheat-sheet

## À quoi ça sert

Monter et exploiter des partages réseau (Samba/CIFS pour Windows, NFS pour Unix),
inspecter les disques et partitions locaux, déclarer un montage permanent dans
`/etc/fstab`, et faire des sauvegardes basiques avec `rsync` ou `tar`. On y touche
pour brancher un NAS sur un hôte, diagnostiquer un montage qui ne tient pas, ou
mettre en place une copie de sécurité.

## Commandes de base

### Samba / CIFS (partages Windows)

```bash
# Lister les partages exposés par un serveur (demande le mot de passe)
smbclient -L //serveur -U user01
smbclient -L //serveur -N                 # -N : tentative anonyme (sans mot de passe)

# Se connecter à un partage en mode interactif (type FTP : ls, get, put...)
smbclient //serveur/partage -U user01

# Vérifier la syntaxe d'un fichier de conf Samba côté serveur (smb.conf)
testparm                                  # affiche la conf interprétée + erreurs
testparm -s                               # sans pause interactive
```

```bash
# Monter un partage CIFS (créer d'abord le point de montage)
mkdir -p /mnt/partage
mount -t cifs //serveur/partage /mnt/partage -o username=user01

# Montage avec options courantes (uid/gid local, version protocole)
mount -t cifs //serveur/partage /mnt/partage \
  -o username=user01,uid=1000,gid=1000,vers=3.0

# Mieux : stocker les identifiants hors ligne de commande (fichier 0600)
#   cat > ~/.smbcreds  -> username=user01 / password=... / domain=...
mount -t cifs //serveur/partage /mnt/partage -o credentials=/root/.smbcreds
```

### NFS (partages Unix)

```bash
# Lister les exports NFS d'un serveur
showmount -e serveur

# Monter un export NFS
mkdir -p /mnt/nfs
mount -t nfs serveur:/chemin/export /mnt/nfs
mount -t nfs -o vers=4 serveur:/chemin/export /mnt/nfs   # forcer NFSv4
```

```bash
# Côté serveur NFS : appliquer les exports déclarés dans /etc/exports
exportfs -ra                              # recharger tous les exports (-r) en silence (-a)
exportfs -v                               # lister les exports actifs et leurs options
```

### Disques et partitions

```bash
lsblk                                     # arborescence disques/partitions (taille, point de montage)
lsblk -f                                  # + système de fichiers et UUID
blkid                                     # UUID et type de FS de chaque partition
blkid /dev/sdb1                           # cibler une partition
df -h                                     # espace utilisé par point de montage
mount                                     # lister tous les montages actifs
umount /mnt/partage                       # démonter
```

### Montage permanent — `/etc/fstab`

```fstab
# <source>                  <point montage>  <type>  <options>                       <dump> <pass>
UUID=xxxx-xxxx-xxxx-xxxx     /mnt/data        ext4    defaults                        0      2
//serveur/partage           /mnt/partage     cifs    credentials=/root/.smbcreds,_netdev  0  0
serveur:/chemin/export      /mnt/nfs         nfs     defaults,_netdev                0      0
```

```bash
mount -a                                  # monter toutes les entrées fstab non encore montées
findmnt --verify                          # vérifier la cohérence de fstab avant reboot
```

### Sauvegarde générique

```bash
# rsync : copie incrémentale (ne recopie que ce qui a changé)
rsync -avh /source/ /destination/         # -a archive, -v verbeux, -h tailles lisibles
rsync -avh --delete /source/ /destination/   # miroir : supprime à destination ce qui n'est plus à la source
rsync -avh -e ssh /source/ user@host:/destination/   # vers un hôte distant via SSH

# tar : archive horodatée
tar czf sauvegarde-$(date +%F).tar.gz /chemin/a/sauvegarder   # créer (gzip)
tar xzf sauvegarde.tar.gz -C /chemin/restauration            # extraire
tar tzf sauvegarde.tar.gz                                     # lister le contenu sans extraire
```

## Pièges fréquents

- **`rsync` et le slash final** : `rsync src/ dest/` copie le *contenu* de `src` dans
  `dest` ; `rsync src dest/` copie le *dossier* `src` dans `dest`. Une étourderie qui
  crée un niveau de dossier en trop ou en moins.
- **`--delete` est destructif** : il efface à la destination tout ce qui n'existe plus
  à la source. Tester d'abord avec `--dry-run` (ou `-n`).
- **Identifiants en clair dans `fstab`/ligne de commande** : un mot de passe dans
  `mount -o password=...` est visible dans l'historique et `ps`. Utiliser un fichier
  `credentials=` en `chmod 600`.
- **`_netdev` oublié dans fstab** : sans cette option, le système tente de monter le
  partage réseau avant que le réseau soit prêt au boot → blocage. Toujours `_netdev`
  pour CIFS/NFS.
- **Version SMB incompatible** : un montage CIFS qui échoue sans raison claire vient
  souvent d'une négociation de protocole ; forcer `vers=3.0` (ou la version supportée).
- **NFS : permissions par UID/GID** : NFS mappe les droits par numéro d'UID/GID, pas
  par nom. Un même nom d'utilisateur avec des UID différents des deux côtés donne des
  accès incohérents.
- **`exportfs -ra` côté serveur après modif** : éditer `/etc/exports` ne suffit pas, il
  faut recharger. Sinon les clients ne voient pas le nouvel export.

## Voir aussi

- [Linux & systemd](./linux-systemd.md) — diagnostic disque (`df`, `du`) et services
- [Réseau & pfSense](./reseau-pfsense.md) — tester la connectivité vers le serveur de stockage
- [Secrets & SSH](./secrets-ssh.md) — `scp`/`sftp` et tunnels pour transferts distants
