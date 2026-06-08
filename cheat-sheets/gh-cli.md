---
title: GitHub CLI (gh)
category: cheat-sheets
tags: [github, gh, cli, pull-request, issue, actions, cheat-sheet]
created: 2026-06-08
---

# GitHub CLI (gh) — Cheat-sheet

## À quoi ça sert

`gh` est le client en ligne de commande de GitHub. Il gère ce que `git` ne fait pas :
authentification au compte, création/clonage de dépôts, pull requests, issues,
exécutions GitHub Actions, et appels bruts à l'API. On l'utilise pour ouvrir une PR
sans quitter le terminal, suivre l'état d'une CI, ou trier des issues.

> Pour les opérations git pures (commit, branches, rebase, push…), voir la fiche
> dédiée : [Git](./git.md). Cette fiche ne couvre **que** ce qui est propre à `gh`.

## Commandes de base

### Authentification

```bash
gh auth login                              # connexion interactive (navigateur ou token)
gh auth status                             # vérifier l'état et le compte connecté
gh auth logout                             # se déconnecter
gh auth token                              # afficher le token actif (à manipuler avec prudence)
```

### Dépôts — `gh repo`

```bash
gh repo clone <owner>/<repo>               # cloner (gère l'auth automatiquement)
gh repo view <owner>/<repo>                # résumé du dépôt dans le terminal
gh repo view <owner>/<repo> --web          # ouvrir dans le navigateur
gh repo create <repo> --private --source=. --push   # créer depuis un dossier local
gh repo fork <owner>/<repo> --clone        # forker et cloner le fork
gh repo list <owner>                        # lister les dépôts d'un compte/orga
```

### Pull requests — `gh pr`

```bash
gh pr create                               # créer une PR (assistant interactif)
gh pr create --title "<titre>" --body "<description>" --base main   # non interactif
gh pr list                                 # lister les PR ouvertes
gh pr list --state all                     # toutes (ouvertes, fermées, mergées)
gh pr status                               # PR qui te concernent (auteur, review demandée)
gh pr view <numéro>                        # détail d'une PR
gh pr checkout <numéro>                     # récupérer localement la branche de la PR
gh pr diff <numéro>                        # voir le diff d'une PR
gh pr merge <numéro>                        # fusionner (assistant : merge/squash/rebase)
gh pr merge <numéro> --squash --delete-branch   # squash + suppression de la branche
```

### Issues — `gh issue`

```bash
gh issue list                              # lister les issues ouvertes
gh issue list --label "<label>"            # filtrer par label
gh issue create --title "<titre>" --body "<description>"
gh issue view <numéro>                      # détail d'une issue
gh issue close <numéro>                     # fermer
gh issue comment <numéro> --body "<texte>"  # commenter
```

### GitHub Actions — `gh run`

```bash
gh run list                                # dernières exécutions de workflows
gh run list --workflow=<fichier>.yml       # filtrer par workflow
gh run view <run-id>                        # détail d'une exécution
gh run view <run-id> --log                  # logs complets
gh run watch <run-id>                       # suivre une exécution en cours en direct
gh run rerun <run-id>                        # relancer une exécution
```

### API brute — `gh api`

```bash
gh api /user                               # appel GET authentifié (utilisateur courant)
gh api /repos/<owner>/<repo>               # métadonnées d'un dépôt
gh api /repos/<owner>/<repo>/issues --paginate   # toutes les pages d'un endpoint
gh api -X POST /repos/<owner>/<repo>/issues -f title="<titre>"   # POST avec champ
```

## Pièges fréquents

- **`gh` n'est pas `git`** : `gh repo clone` configure l'auth, mais commit/push/branche
  restent du ressort de `git`. Ne pas chercher d'équivalent `gh commit`.
- **Authentification distincte de git** : `gh auth login` authentifie `gh` ; cela ne
  configure pas forcément les credentials git pour `https://` (sauf si on laisse `gh`
  s'en charger via `gh auth setup-git`).
- **Token affiché en clair** : `gh auth token` imprime le secret dans le terminal et
  l'historique. À éviter ; si besoin, le rediriger vers un usage immédiat sans le logger.
- **`gh pr create` cible la mauvaise base** : par défaut la base est la branche par
  défaut du dépôt parent (utile pour les forks, surprenant sinon). Préciser `--base`.
- **Numéro de PR vs numéro d'issue** : ils partagent le même espace de numérotation sur
  GitHub ; une commande `gh pr view <n>` sur un numéro d'issue échoue.
- **Forge auto-hébergée ≠ GitHub** : `gh` parle l'API GitHub. Pour une forge
  auto-hébergée (Gitea, GitLab…), utiliser son propre CLI ou son API ; se
  reporter à sa documentation officielle.

## Voir aussi

- [Git](./git.md) — toutes les opérations git (commit, branches, rebase, push, PR locale)
- [Secrets & SSH](./secrets-ssh.md) — clés SSH pour `git@github.com` et gestion du token
