---
title: Splunk (administration / CLI)
category: cheat-sheets
tags: [splunk, siem, cli, administration, cheat-sheet]
created: 2026-06-08
---

# Splunk (administration / CLI) — Cheat-sheet

## À quoi ça sert

Côté **administration** d'une instance Splunk : démarrer/arrêter le service, vérifier
la configuration effective (qui peut venir de plusieurs apps qui se superposent),
lancer une recherche depuis la ligne de commande, gérer index et entrées de config,
et diagnostiquer via l'index interne `_internal` et les logs de `splunkd`.

Cette fiche couvre **uniquement le CLI d'admin**, pas le langage de recherche SPL.
Pour écrire des recherches → voir [Voir aussi](#voir-aussi).

Toutes les commandes ci-dessous s'invoquent via le binaire `splunk`, généralement sous
`$SPLUNK_HOME/bin/splunk` (souvent `/opt/splunk/bin/splunk`).

## Commandes de base

### Cycle de vie du service

```bash
splunk start                         # démarrer splunkd (+ accepter la licence au 1er lancement)
splunk stop                          # arrêter
splunk restart                       # redémarrer
splunk status                        # état des processus (splunkd, éventuel web)
splunk version                       # version de l'instance
```

### Authentification des commandes

La plupart des commandes d'admin exigent une authentification. Trois formes :

```bash
# 1. Interactif : Splunk demande login/mot de passe
splunk list index

# 2. En une ligne (à éviter en clair : visible dans l'historique et la liste des process)
splunk list index -auth admin:"$SPLUNK_PASSWORD"

# 3. Session pré-ouverte : évite de repasser -auth à chaque commande
splunk login -auth admin:"$SPLUNK_PASSWORD"
splunk list index                    # réutilise la session courante
```

### Vérifier la configuration effective — `btool`

`btool` montre la valeur **résolue** d'une configuration après empilement de toutes les
apps et de leurs priorités (le « pourquoi cette valeur s'applique »).

```bash
splunk btool <conf> list             # config résolue d'un fichier .conf (sans .conf)
splunk btool inputs list             # ex : entrées de collecte effectives
splunk btool server list --debug     # --debug : préfixe chaque ligne par son fichier source
splunk btool props list <stanza>     # se limiter à une stanza précise
splunk btool check                   # détecter les erreurs de syntaxe dans les .conf
```

### Recherche depuis le CLI

```bash
# Recherche ponctuelle (le SPL passe entre guillemets ; -auth si pas de session)
splunk search 'index=<index> error | head 20' -auth admin:"$SPLUNK_PASSWORD"

# Recherche temps réel / fenêtre explicite
splunk search 'index=<index> | stats count' -earliest_time -1h -latest_time now

# Format de sortie
splunk search 'index=<index> | head 5' -output csv     # format de sortie (ex. table, csv)
splunk search 'index=<index> | head 5' -maxout 0       # ne pas tronquer (0 = illimité)
```

### Gérer index et entrées de config — `add` / `edit` / `list` / `remove`

```bash
splunk list index                                # lister les index
splunk add index <index>                         # créer un index
splunk edit index <index> -maxTotalDataSizeMB 5000   # modifier un paramètre d'index
splunk remove index <index>                      # supprimer un index (destructif)

splunk list monitor                              # entrées de monitoring de fichiers
splunk add monitor /var/log/<app>                # ajouter une surveillance de fichier/dossier
splunk add forward-server example.com:9997       # déclarer un indexer de réception (forwarder)
splunk list forward-server
```

### Inspecter et tester la config — `show` / `cmd`

```bash
splunk show config <conf>                        # afficher une config (ex : inputs, server)
splunk show splunkd-port                         # port de gestion (par défaut 8089)
splunk show web-port                             # port de l'interface web (par défaut 8000)

# splunk cmd : lancer un outil livré avec Splunk dans son environnement (PATH, libs)
splunk cmd btool inputs list                     # équivalent à btool, via cmd
splunk cmd splunkd ...                            # lancer splunkd avec l'environnement Splunk
```

### Diagnostic — index `_internal` et `splunkd.log`

```bash
# Erreurs récentes vues par Splunk lui-même (logs ingérés dans l'index interne)
splunk search 'index=_internal source=*splunkd.log* log_level=ERROR | head 50' \
  -auth admin:"$SPLUNK_PASSWORD"

# Lecture directe du fichier de log (pas d'auth nécessaire, accès fichier)
tail -f $SPLUNK_HOME/var/log/splunk/splunkd.log
```

## Pièges fréquents

- **`-auth` en clair fuite le mot de passe** : il apparaît dans l'historique shell et
  dans la liste des processus (`ps`). Préférer `splunk login` une fois, ou une variable
  d'environnement (`$SPLUNK_PASSWORD`) renseignée hors historique.
- **Confondre la config disque et la config effective** : un `.conf` peut être écrasé par
  une app plus prioritaire. Toujours valider avec `btool <conf> list --debug` (qui montre
  le fichier source), pas en lisant un seul fichier.
- **Oublier `btool check` après édition manuelle** : une stanza mal formée empêche
  `splunkd` de démarrer. Vérifier la syntaxe avant `restart`.
- **`remove index` détruit les données** : la suppression d'un index efface ses buckets.
  Aucun retour en arrière sans sauvegarde du stockage.
- **Recherche CLI tronquée** : par défaut le CLI limite le nombre de résultats. Utiliser
  `-maxout 0` pour une extraction complète.
- **Confondre port web (8000) et port de gestion (8089)** : les commandes/API d'admin et
  les forwarders parlent au port de gestion (`example.com:8089`), pas à l'interface web.
- **Restart nécessaire ou pas** : certaines configs (inputs, props) sont rechargées à
  chaud via l'endpoint de reload ; d'autres exigent un `splunk restart`. Vérifier la doc
  de la stanza concernée avant de redémarrer en prod. En cluster, ce n'est **pas l'acte
  de pousser un bundle** qui déclenche un restart mais le **contenu** : seules les confs
  « ne supportant pas le reload » forcent un rolling restart (SHC : flag
  `advertiseRestartRequired` côté membre ; IDXC : reloader de conf côté peer). Une même
  conf peut RELOAD sur un SHC et RESTART sur un cluster d'indexers. Table de vérité par
  conf, méthode pour la déterminer soi-même, et pièges (purge d'app, suppression d'index,
  searchable rolling restart) : [Déclencheurs de rolling restart — SHC & cluster
  d'indexers](../splunk/concepts/rolling-restart-triggers.md).

## Voir aussi

- [Splunk — concepts & SPL](../splunk/README.md) — architecture, indexers, et le **langage de recherche SPL** (cette fiche ne couvre pas le SPL).
- [Linux & systemd](./linux-systemd.md) — gérer le service `splunkd` sous systemd, lire les logs hôte.
- [Secrets & SSH](./secrets-ssh.md) — stocker le mot de passe admin hors historique (`$SPLUNK_PASSWORD`).
