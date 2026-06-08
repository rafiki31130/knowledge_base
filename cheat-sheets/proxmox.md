---
title: Proxmox VE
category: cheat-sheets
tags: [proxmox, virtualisation, kvm, lxc, cheat-sheet]
created: 2026-06-08
---

# Proxmox VE — Cheat-sheet

## À quoi ça sert

Proxmox VE est un hyperviseur qui gère des machines virtuelles (KVM, outil `qm`) et
des conteneurs (LXC, outil `pct`) depuis l'interface web ou la ligne de commande.
On touche ces commandes pour piloter le cycle de vie des VM/CT, gérer le stockage,
faire des sauvegardes et diagnostiquer un nœud quand l'interface web est indisponible.

## Commandes de base

### VM (KVM) — `qm`

```bash
qm list                              # lister les VM du nœud (VMID, nom, statut, RAM)
qm status <vmid>                     # statut d'une VM
qm start <vmid>                      # démarrer
qm stop <vmid>                       # arrêt brutal (coupure d'alimentation)
qm shutdown <vmid>                   # arrêt propre via ACPI (invité doit coopérer)
qm reboot <vmid>                     # redémarrage propre
qm config <vmid>                     # afficher la config (CPU, RAM, disques, réseau)
qm set <vmid> --memory 4096          # modifier un paramètre (ex : RAM en Mo)
```

```bash
# Cloner une VM (clone complet par défaut)
qm clone <vmid> <nouveau_vmid> --name <nom> --full
qm clone <vmid> <nouveau_vmid> --name <nom>     # clone lié (linked clone) si modèle

# Migrer une VM vers un autre nœud du cluster
qm migrate <vmid> <noeud_cible>                 # à froid (VM arrêtée)
qm migrate <vmid> <noeud_cible> --online        # à chaud (live migration)
```

```bash
# Snapshots
qm listsnapshot <vmid>                          # lister les snapshots
qm snapshot <vmid> <nom_snap> --description "<texte>"
qm snapshot <vmid> <nom_snap> --vmstate 1       # inclure l'état RAM (VM en marche)
qm rollback <vmid> <nom_snap>                   # restaurer un snapshot
qm delsnapshot <vmid> <nom_snap>                # supprimer un snapshot
```

### Conteneurs (LXC) — `pct`

```bash
pct list                             # lister les conteneurs (CTID, statut, nom)
pct status <ctid>                    # statut d'un conteneur
pct start <ctid>                     # démarrer
pct stop <ctid>                      # arrêt brutal
pct shutdown <ctid>                  # arrêt propre
pct config <ctid>                    # afficher la config
pct enter <ctid>                     # ouvrir un shell dans le conteneur
pct exec <ctid> -- <commande>        # exécuter une commande dans le conteneur
```

### Stockage — `pvesm`

```bash
pvesm status                         # état des stockages (type, total, utilisé, dispo)
pvesm list local-lvm                 # lister les volumes d'un stockage
```

### Sauvegarde / restauration — `vzdump`

```bash
# Sauvegarder une VM ou un conteneur (même outil pour les deux)
vzdump <vmid> --storage <stockage> --mode snapshot --compress zstd
vzdump <ctid> --storage <stockage> --mode stop        # arrête le CT le temps du dump

# Restaurer une VM KVM depuis une archive
qmrestore /chemin/vers/vzdump-qemu-<vmid>-*.vma.zst <nouveau_vmid> --storage local-lvm

# Restaurer un conteneur LXC depuis une archive
pct restore <nouveau_ctid> /chemin/vers/vzdump-lxc-<ctid>-*.tar.zst --storage local-lvm
```

### Version et infos nœud

```bash
pveversion                           # version courte de Proxmox VE
pveversion -v                        # versions détaillées (kernel, qemu, paquets)
pvecm status                         # état du cluster (si nœud en cluster)
```

## Pièges fréquents

- **`qm stop` ≠ `qm shutdown`** : `stop` coupe l'alimentation (risque de corruption FS) ;
  préférer `shutdown` (ACPI) sauf VM bloquée. `shutdown` exige que l'invité gère l'ACPI.
- **Snapshot ≠ sauvegarde** : un snapshot vit sur le même stockage que le disque ;
  si le stockage meurt, le snapshot meurt avec. Pour une vraie sauvegarde, `vzdump`.
- **Snapshot oublié = espace qui gonfle** : un snapshot laissé en place accumule les
  deltas et peut saturer `local-lvm`. Lister régulièrement avec `qm listsnapshot`.
- **`--vmstate` consomme de la RAM disque** : inclure l'état RAM dans un snapshot écrit
  toute la mémoire de la VM sur le stockage ; inutile pour un snapshot de VM arrêtée.
- **Live migration et stockage local** : `--online` exige un stockage partagé ou la
  réplication ; un disque purement local doit être migré (copié), ce qui est plus lent.
- **VMID/CTID partagent l'espace de noms** : un même identifiant ne peut pas être à la
  fois une VM et un conteneur. Vérifier avec `qm list` et `pct list` avant d'attribuer.

## Voir aussi

- [Linux & systemd](./linux-systemd.md) — gérer les services à l'intérieur d'une VM/CT
- [Docker](./docker.md) — conteneurs applicatifs (souvent dans une VM Proxmox)
- [Réseau & pfSense](./reseau-pfsense.md) — diagnostic réseau d'un nœud ou d'un invité
