---
title: Ansible
category: cheat-sheets
tags: [ansible, automation, playbook, vault, galaxy, cheat-sheet]
created: 2026-06-08
---

# Ansible — Cheat-sheet

## À quoi ça sert

Ansible automatise la configuration de machines distantes par SSH, de façon
idempotente, à partir de playbooks YAML. On l'utilise pour appliquer une config
sur un parc, lancer une commande ponctuelle sur plusieurs hôtes (ad-hoc), chiffrer
des données sensibles dans le repo (`ansible-vault`) et installer des rôles/collections
réutilisables (`ansible-galaxy`). Les commandes ci-dessous couvrent l'exécution
courante, pas l'écriture des rôles.

## Commandes de base

### Exécuter un playbook — `ansible-playbook`

```bash
ansible-playbook -i <inventory> <playbook>            # exécution standard
ansible-playbook -i <inventory> <playbook> --check    # simulation (dry-run), ne change rien
ansible-playbook -i <inventory> <playbook> --diff     # montrer les changements ligne à ligne
ansible-playbook -i <inventory> <playbook> --check --diff   # combo : prévisualiser sans appliquer
```

```bash
# Cibler / filtrer
ansible-playbook -i <inventory> <playbook> --limit <host>   # restreindre à un hôte ou groupe
ansible-playbook -i <inventory> <playbook> --tags <tag>     # ne jouer que les tâches taguées
ansible-playbook -i <inventory> <playbook> --skip-tags <tag># tout sauf ces tags
ansible-playbook -i <inventory> <playbook> --list-tasks     # lister les tâches sans exécuter
ansible-playbook -i <inventory> <playbook> --list-hosts     # voir quels hôtes seraient ciblés
```

```bash
# Verbosité et privilèges
ansible-playbook -i <inventory> <playbook> -v          # verbeux (-vvv pour le débogage SSH)
ansible-playbook -i <inventory> <playbook> -b          # devenir root (become / sudo)
ansible-playbook -i <inventory> <playbook> -K          # demander le mot de passe sudo (--ask-become-pass)
```

### Commandes ad-hoc — `ansible`

```bash
ansible all -i <inventory> -m ping                     # tester la connectivité (module ping)
ansible <host> -i <inventory> -m shell -a "uptime"     # exécuter une commande shell
ansible <host> -i <inventory> -m command -a "df -h"    # module command (sans shell, plus sûr)
ansible all -i <inventory> -m setup                    # collecter les facts d'un hôte
ansible all -i <inventory> --list-hosts                # lister les hôtes de l'inventaire
```

### Secrets — `ansible-vault`

```bash
ansible-vault encrypt <fichier>            # chiffrer un fichier de variables
ansible-vault decrypt <fichier>            # déchiffrer (revient en clair sur disque)
ansible-vault view <fichier>               # afficher en clair sans modifier le fichier
ansible-vault edit <fichier>               # éditer en place (déchiffre, ouvre, rechiffre)
ansible-vault rekey <fichier>              # changer le mot de passe de vault
ansible-vault create <fichier>             # créer un nouveau fichier chiffré
```

```bash
# Fournir le mot de passe de vault sans le saisir interactivement
ansible-playbook -i <inventory> <playbook> --ask-vault-pass          # demande à l'invite
ansible-playbook -i <inventory> <playbook> --vault-password-file <fichier>
                                           # lit le mot de passe dans un fichier (hors repo, chmod 600)
```

### Rôles et collections — `ansible-galaxy`

```bash
ansible-galaxy install <namespace>.<role>            # installer un rôle depuis Galaxy
ansible-galaxy install -r requirements.yml           # installer tout ce qui est listé
ansible-galaxy collection install <namespace>.<collection>   # installer une collection
ansible-galaxy list                                  # lister les rôles installés
ansible-galaxy role init <nom_role>                  # squelette d'un nouveau rôle
```

## Pièges fréquents

- **`--check` n'est pas fiable à 100 %** : les tâches qui dépendent d'un résultat
  précédent (commande shell, registre) peuvent mal se simuler. Le dry-run prévient,
  il ne garantit pas. Combiner avec `--diff` et relire.
- **Mot de passe de vault dans le repo** : ne jamais commiter le `--vault-password-file`.
  Le fichier de mot de passe vit hors du repo, en `chmod 600`. Seuls les fichiers
  *chiffrés* par vault vont dans le dépôt.
- **`-m shell` vs `-m command`** : `command` n'interprète pas les pipes, variables et
  redirections ; `shell` oui mais expose aux injections. Préférer `command` quand on
  n'a pas besoin du shell.
- **Idempotence cassée par `shell`/`command`** : ces modules tournent à chaque
  exécution et rapportent toujours « changed ». Utiliser `creates=`/`removes=` ou un
  module dédié pour rester idempotent.
- **Inventaire implicite oublié** : sans `-i`, Ansible utilise l'inventaire par défaut
  (souvent `/etc/ansible/hosts`), pas celui du projet. Toujours préciser `-i`.
- **`--limit` avec un nom inexistant** : si le motif ne matche aucun hôte, Ansible ne
  fait rien sans erreur évidente. Vérifier avec `--list-hosts` avant.
- **`become` (sudo) requis mais absent** : une tâche qui modifie le système échoue en
  « permission denied » si `-b` manque. Le `become` se met au niveau play ou tâche.

## Voir aussi

- [Secrets & SSH](./secrets-ssh.md) — Ansible se connecte par SSH ; clés, agent, `~/.ssh/config`
- [Linux & systemd](./linux-systemd.md) — ce qu'Ansible pilote sur les hôtes (services, paquets)
- [Git](./git.md) — versionner playbooks et rôles (fichiers vault chiffrés inclus)
