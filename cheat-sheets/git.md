---
title: Git
category: cheat-sheets
tags: [git, vcs, cheat-sheet]
created: 2026-05-23
---

# Git — Cheat-sheet

## Écraser un remote avec un dépôt local neuf

Initialiser localement et forcer le push, remplaçant définitivement le contenu distant.

```bash
cd /chemin/dossier-local
git init
git add .
git commit -m "Initial commit"
git remote add origin <URL_DU_REMOTE>
git branch -M main
git push --force origin main
```

`--force-with-lease` : variante prudente, échoue si le remote a divergé. Inadaptée à un écrasement volontaire.
Si le push est rejeté : branche protégée côté serveur (GitHub/GitLab/Bitbucket) → désactiver la protection, pousser, réactiver.

## Configuration initiale

```bash
git config --global user.name "Nom"
git config --global user.email "mail@exemple.fr"
git config --global init.defaultBranch main
git config --global pull.rebase true        # rebase au lieu de merge sur pull
git config --list
```

## Démarrer un dépôt

```bash
git init                          # nouveau dépôt local
git clone <url>                   # cloner un remote
git clone <url> <dossier>         # cloner dans un dossier nommé
git clone --depth 1 <url>         # clone superficiel (dernier commit)
```

## État et inspection

```bash
git status
git status -s                     # format court
git diff                          # modifications non indexées
git diff --staged                 # modifications indexées
git log --oneline --graph --all   # historique condensé visuel
git log -p <fichier>              # historique avec diffs d'un fichier
git show <commit>                 # détail d'un commit
git blame <fichier>               # qui a modifié quelle ligne
```

## Indexation et commit

```bash
git add <fichier>
git add .                         # tout le répertoire courant
git add -p                        # indexation interactive par morceaux
git commit -m "message"
git commit -am "message"          # add (fichiers suivis) + commit
git commit --amend                # modifier le dernier commit
git commit --amend --no-edit      # ajouter au dernier commit sans changer le message
```

## Branches

```bash
git branch                        # lister
git branch <nom>                  # créer
git switch <nom>                  # changer (moderne)
git switch -c <nom>               # créer et changer
git checkout <nom>                # changer (ancien)
git checkout -b <nom>             # créer et changer (ancien)
git branch -d <nom>               # supprimer (sécurisé)
git branch -D <nom>               # supprimer (forcé)
git branch -m <ancien> <nouveau>  # renommer
```

## Fusion et rebase

```bash
git merge <branche>               # fusionner dans la branche courante
git merge --no-ff <branche>       # fusion avec commit de merge explicite
git rebase <branche>              # rejouer les commits sur <branche>
git rebase -i HEAD~3              # rebase interactif (squash, reword, drop...)
git rebase --abort                # annuler un rebase en cours
git rebase --continue             # reprendre après résolution de conflit
```

## Remotes

```bash
git remote -v                     # lister
git remote add origin <url>
git remote set-url origin <url>   # changer l'URL
git remote remove origin
git fetch                         # récupérer sans fusionner
git pull                          # fetch + merge/rebase
git push                          # pousser
git push -u origin <branche>      # pousser et suivre la branche
git push --force origin <branche> # écraser le remote
git push --tags                   # pousser les tags
```

## Annuler / corriger

```bash
git restore <fichier>             # annuler modifs non indexées (moderne)
git restore --staged <fichier>    # désindexer
git checkout -- <fichier>         # annuler modifs (ancien)
git reset <fichier>               # désindexer (ancien)
git reset --soft HEAD~1           # annuler dernier commit, garder modifs indexées
git reset --mixed HEAD~1          # annuler dernier commit, garder modifs non indexées
git reset --hard HEAD~1           # annuler dernier commit ET les modifs (destructif)
git revert <commit>               # annuler un commit via un nouveau commit (sûr)
git clean -fd                     # supprimer fichiers/dossiers non suivis (destructif)
```

## Stash

```bash
git stash                         # remiser les modifs en cours
git stash -u                      # inclure les fichiers non suivis
git stash list
git stash pop                     # restaurer et retirer de la pile
git stash apply                   # restaurer sans retirer
git stash drop                    # supprimer le dernier stash
```

## Tags

```bash
git tag                           # lister
git tag <nom>                     # tag léger
git tag -a v1.0 -m "version 1.0"  # tag annoté
git push origin <tag>
git tag -d <nom>                  # supprimer localement
git push origin --delete <tag>    # supprimer sur le remote
```

## Récupération

```bash
git reflog                        # historique de tous les déplacements de HEAD
git reset --hard <hash>           # revenir à un état depuis le reflog
git cherry-pick <commit>          # appliquer un commit isolé sur la branche courante
```

`git reflog` permet de retrouver des commits "perdus" après un reset --hard ou un rebase raté, tant que le garbage collector n'est pas passé (~30 jours par défaut).

## Enchaînements classiques (sur lesquels la plupart butent)

### Pousser une nouvelle branche locale vers le remote

```bash
git switch -c ma-feature
# ...commits...
git push -u origin ma-feature     # -u crée le suivi : ensuite `git push` suffit
```

### Récupérer une branche distante créée par un collègue

```bash
git fetch origin
git switch ma-feature             # crée la branche locale qui suit origin/ma-feature
# variante explicite :
git switch -c ma-feature --track origin/ma-feature
```

### Mettre à jour sa branche avec `main` (rebase propre)

```bash
git fetch origin
git rebase origin/main
# en cas de conflit :
#   éditer les fichiers, puis :
git add <fichier-résolu>
git rebase --continue
# si on s'embourbe :
git rebase --abort
```

### Re-pousser après un rebase (sans écraser le travail d'autrui)

```bash
git push --force-with-lease       # refuse de pousser si quelqu'un d'autre a poussé entre-temps
```
À préférer systématiquement à `--force` sur une branche partagée (PR).

### J'ai commité sur `main` par erreur, je veux déplacer ces commits sur une branche

```bash
git branch ma-feature             # crée la branche au HEAD actuel (garde les commits)
git reset --hard origin/main      # remet main à l'état du remote
git switch ma-feature             # le travail est ici
```

### Squash des N derniers commits en un seul

```bash
git rebase -i HEAD~3
# dans l'éditeur : laisser "pick" sur le 1er, mettre "squash" (ou "s") sur les suivants
# sauvegarder, puis éditer le message final
```

### Annuler un commit déjà poussé (sans réécrire l'historique)

```bash
git revert <hash>                 # crée un commit qui inverse les changements
git push
```

### Récupérer un seul fichier depuis une autre branche

```bash
git checkout autre-branche -- chemin/fichier
# ou (moderne) :
git restore --source=autre-branche -- chemin/fichier
```

### Sortir d'un état "detached HEAD" sans perdre le travail

```bash
git switch -c sauvegarde          # transforme l'état détaché en vraie branche
```

### Résoudre un conflit pendant un merge

```bash
git merge ma-branche
# conflits → éditer les fichiers (chercher <<<<<<<)
git add <fichier-résolu>
git commit                        # message de merge pré-rempli
# ou tout annuler :
git merge --abort
```

### Renommer une branche locale ET côté remote

```bash
git branch -m ancien nouveau
git push origin -u nouveau
git push origin --delete ancien
```

### Synchroniser un fork avec l'upstream

```bash
git remote add upstream <url-du-repo-original>     # une fois pour toutes
git fetch upstream
git switch main
git rebase upstream/main          # ou : git merge upstream/main
git push                          # met à jour le fork
```

### Supprimer un fichier sensible déjà commité (et le .gitignore-er)

```bash
echo ".env" >> .gitignore
git rm --cached .env
git commit -m "Retire .env du suivi"
git push
```
Le fichier reste dans l'historique. Pour purge complète : `git filter-repo` (rotation des secrets recommandée à la place).

### "Oups, j'ai fait `reset --hard`, j'ai tout perdu"

```bash
git reflog                        # repérer le hash d'avant le reset
git reset --hard <hash>
```

### Mettre de côté pour faire un `git pull` rapide

```bash
git stash -u
git pull --rebase
git stash pop
# si conflit au pop : résoudre, puis `git stash drop` pour nettoyer
```

### Réécrire le message du dernier commit (déjà poussé)

```bash
git commit --amend -m "Nouveau message"
git push --force-with-lease
```

### Supprimer toutes les branches locales déjà fusionnées

```bash
git branch --merged main | grep -v '^\*\| main$' | xargs -n 1 git branch -d
```

## .gitignore

```bash
# Fichier
*.log
.env
node_modules/

# Exception
!important.log

# Cesser de suivre un fichier déjà commité après l'avoir ajouté au .gitignore
git rm --cached <fichier>
```
