---
title: Secrets (1Password CLI) & SSH
category: cheat-sheets
tags: [secrets, 1password, op, ssh, ssh-config, tunnels, scp, cheat-sheet]
created: 2026-06-08
---

# Secrets (1Password CLI) & SSH — Cheat-sheet

## À quoi ça sert

Deux besoins liés : récupérer des secrets sans les écrire en clair (1Password CLI
`op`, qui lit un coffre depuis le terminal et peut injecter des secrets dans une
commande), et se connecter à des machines distantes en SSH (clés, fichier de config
avec alias, agent, tunnels, copie de fichiers). On y touche pour scripter un accès
sécurisé ou ouvrir un tunnel vers un service distant.

> **Aucune valeur réelle dans cette fiche.** Tous les coffres, items, champs, hôtes
> et alias sont des placeholders (`op://<vault>/<item>/<field>`, `<alias>`,
> `user@host`). Ne jamais commiter un secret, un vrai chemin `op://`, ni un alias
> d'infrastructure réel.

## Commandes de base

### 1Password CLI — `op`

```bash
op signin                                  # ouvrir une session (selon la conf du compte)
op vault list                              # lister les coffres accessibles
op item list                               # lister les items (du coffre par défaut)
op item list --vault <vault>               # lister les items d'un coffre précis
op item get <item>                         # afficher un item (champs non secrets)
op item get <item> --fields label=<field> # extraire un champ précis
```

```bash
# Lire directement la valeur d'un champ par sa référence secrète
op read "op://<vault>/<item>/<field>"
# Exemple de forme (placeholders) : un mot de passe, une clé d'API, un token...
```

```bash
# Injecter des secrets dans une commande sans les exposer dans l'environnement
op run -- <commande>                       # résout les références op:// présentes dans l'env
# Modèle : un fichier .env contient FOO=op://<vault>/<item>/<field>
op run --env-file=.env -- <commande>       # les références sont résolues le temps de la commande
```

### SSH — clés

```bash
ssh-keygen -t ed25519 -C "<commentaire>"   # générer une paire de clés Ed25519 (recommandé)
ssh-keygen -t ed25519 -f ~/.ssh/<nom_cle>  # nommer explicitement le fichier de clé
ssh-keygen -y -f ~/.ssh/<nom_cle>          # réafficher la clé publique à partir de la privée
ssh-keygen -p -f ~/.ssh/<nom_cle>          # changer la passphrase d'une clé existante

ssh-copy-id user@host                      # déposer sa clé publique sur l'hôte distant
ssh-copy-id -i ~/.ssh/<nom_cle>.pub user@host   # préciser quelle clé publique copier
```

### SSH — agent

```bash
eval "$(ssh-agent -s)"                      # démarrer l'agent dans le shell courant
ssh-add ~/.ssh/<nom_cle>                    # charger une clé (saisie de la passphrase une fois)
ssh-add -l                                  # lister les clés chargées
ssh-add -D                                  # décharger toutes les clés
```

### SSH — `~/.ssh/config`

```sshconfig
# Un bloc Host crée un alias : « ssh <alias> » applique ces réglages
Host <alias>
    HostName        host.example.com
    User            user01
    Port            22
    IdentityFile    ~/.ssh/<nom_cle>
    IdentitiesOnly  yes               # n'essaie que cette clé (évite « too many auth failures »)

# Rebond via une machine intermédiaire
Host <alias-interne>
    HostName        10.0.0.10
    User            user01
    ProxyJump       <alias>           # passe par l'hôte « <alias> » défini plus haut
```

```bash
ssh <alias>                                # se connecter via l'alias défini
ssh -v <alias>                             # mode verbeux (diagnostic d'authentification)
```

### SSH — tunnels et copie de fichiers

```bash
# Tunnel local (-L) : exposer un service distant sur un port local
ssh -L <port_local>:<host_cible>:<port_cible> user@host
#   ex : accéder à un service tournant sur l'hôte distant via localhost:<port_local>

# Tunnel distant (-R) : exposer un service local sur l'hôte distant
ssh -R <port_distant>:localhost:<port_local> user@host

ssh -N -L <port_local>:<host_cible>:<port_cible> user@host   # -N : tunnel seul, pas de shell
```

```bash
# Copier des fichiers
scp fichier user@host:/chemin/distant/     # envoyer un fichier
scp user@host:/chemin/distant/fichier .    # récupérer un fichier
scp -r dossier/ user@host:/chemin/distant/ # récursif (dossier entier)
scp -P <port> fichier user@host:/chemin/   # -P majuscule pour scp (port non standard)

sftp user@host                             # session interactive (get, put, ls, cd...)
```

## Pièges fréquents

- **`op read` dans un script qui logge** : si la commande est tracée (`set -x`, CI
  verbeuse), la valeur du secret fuit dans les logs. Préférer `op run` qui injecte
  sans imprimer, et ne jamais `echo` un secret.
- **Référence `op://` codée en dur et committée** : même si `op://` n'est pas le secret
  lui-même, recopier des chemins réels révèle la structure du coffre. Garder des
  placeholders dans tout fichier versionné.
- **`scp -P` vs `ssh -p`** : le port se note `-P` (majuscule) avec `scp` mais `-p`
  (minuscule) avec `ssh`. Inversion = échec silencieux de connexion.
- **`-L` vs `-R` confondus** : `-L` ramène un service distant vers chez soi ; `-R`
  pousse un service local vers le distant. Se tromper ouvre le mauvais sens du tunnel.
- **Permissions trop ouvertes sur `~/.ssh`** : SSH refuse une clé privée lisible par
  d'autres. Imposer `chmod 600 ~/.ssh/<nom_cle>` et `700 ~/.ssh`.
- **Passphrase redemandée à chaque connexion** : sans agent, la clé protégée par
  passphrase est redemandée. Charger la clé une fois avec `ssh-add`.
- **`IdentitiesOnly` absent** : sans cette option, SSH propose toutes les clés de
  l'agent et peut être rejeté après trop de tentatives. La fixer par hôte.

## Voir aussi

- [Git](./git.md) — clés SSH pour les remotes `git@…` et écrasement de remote
- [Ansible](./ansible.md) — Ansible se connecte par SSH (mêmes clés, agent, config)
- [Stockage & NAS](./stockage-nas.md) — `scp`/`rsync -e ssh` pour transférer vers un partage
