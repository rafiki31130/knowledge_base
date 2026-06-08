---
title: Home Assistant (CLI & API)
category: cheat-sheets
tags: [home-assistant, domotique, cli, api, yaml, cheat-sheet]
created: 2026-06-08
---

# Home Assistant (CLI & API) — Cheat-sheet

## À quoi ça sert

Home Assistant pilote la domotique (capteurs, automatisations, intégrations). Côté
exploitation on touche : la **CLI `ha`** (présente sur les installations supervisées —
Home Assistant OS / Supervised) pour gérer le cœur, le superviseur et l'hôte ; la
**vérification de configuration** avant un redémarrage ; l'**API REST** pour lire des
états ou déclencher des services ; et le **rechargement à chaud** du YAML.

L'API REST attend un jeton (`Authorization: Bearer <token>`) gardé en variable
d'environnement (`$HA_TOKEN`). Base type : `http://homeassistant.example.com:8123`.

## Commandes de base

### CLI `ha` (installations supervisées)

```bash
# Cœur Home Assistant (core)
ha core check                        # valider la configuration AVANT de redémarrer
ha core restart                      # redémarrer le cœur
ha core logs                         # logs du cœur
ha core info                         # version, état du cœur

# Superviseur
ha supervisor logs                   # logs du superviseur
ha supervisor info                   # état/version du superviseur

# Hôte (machine sous-jacente)
ha host info                         # infos hôte (OS, disque, kernel)
ha host reboot                       # redémarrer la machine hôte

# Add-ons
ha addons                            # lister les add-ons installés
ha addons info <addon>               # détails d'un add-on
ha addons restart <addon>            # redémarrer un add-on
```

### Vérifier la configuration — `hass --script check_config`

Sur une installation **Core** (sans superviseur, ex. dans un venv ou un conteneur Core) :

```bash
hass --script check_config           # valider toute la configuration
hass --script check_config -c <dir>  # préciser le dossier de config
hass --script check_config --info all   # détailler ce qui est chargé
```

### API REST

```bash
# En-têtes communs : Bearer token + Content-Type JSON
# (réutilisés dans les exemples ci-dessous)

# Vérifier que l'API répond
curl -s -H "Authorization: Bearer $HA_TOKEN" \
     "http://homeassistant.example.com:8123/api/"

# Lire l'état de toutes les entités
curl -s -H "Authorization: Bearer $HA_TOKEN" \
     "http://homeassistant.example.com:8123/api/states"

# Lire l'état d'une entité précise
curl -s -H "Authorization: Bearer $HA_TOKEN" \
     "http://homeassistant.example.com:8123/api/states/<domain>.<entity>"

# Appeler un service (POST) : domaine/service dans l'URL, cible dans le corps
curl -s -X POST \
     -H "Authorization: Bearer $HA_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"entity_id": "<domain>.<entity>"}' \
     "http://homeassistant.example.com:8123/api/services/<domain>/<service>"

# Exemple : allumer une lumière
curl -s -X POST \
     -H "Authorization: Bearer $HA_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"entity_id": "light.<entity>"}' \
     "http://homeassistant.example.com:8123/api/services/light/turn_on"
```

### Recharger le YAML à chaud (sans redémarrer le cœur)

Via l'API, en appelant les services de rechargement du domaine concerné :

```bash
# Recharger les automatisations
curl -s -X POST -H "Authorization: Bearer $HA_TOKEN" \
     "http://homeassistant.example.com:8123/api/services/automation/reload"

# Recharger les templates
curl -s -X POST -H "Authorization: Bearer $HA_TOKEN" \
     "http://homeassistant.example.com:8123/api/services/template/reload"

# Recharger les scripts / les groupes / les scènes (même schéma)
curl -s -X POST -H "Authorization: Bearer $HA_TOKEN" \
     "http://homeassistant.example.com:8123/api/services/script/reload"
```

Ces rechargements sont aussi accessibles depuis l'interface (Outils de développement →
YAML), et certains via la CLI selon l'installation.

## Pièges fréquents

- **Toujours `ha core check` (ou `check_config`) avant `restart`** : une erreur YAML
  empêche le cœur de redémarrer. Valider d'abord évite de se retrouver avec un HA à terre.
- **`ha` absent sur une installation Core** : la CLI `ha` n'existe que sur les variantes
  supervisées (HAOS / Supervised). Sur Core, utiliser `hass --script check_config` et les
  services de reload de l'API.
- **Token expiré / révoqué** : les jetons d'accès longue durée se créent dans le profil
  utilisateur. Un 401 vient presque toujours d'un `$HA_TOKEN` invalide ou mal passé.
- **Reload qui ne suffit pas** : tout n'est pas rechargeable à chaud. Les changements de
  certaines intégrations ou de `configuration.yaml` racine exigent un redémarrage complet.
- **Confondre `entity_id` et `device`** : l'API et les automatisations ciblent des
  `entity_id` (`<domain>.<entity>`), pas le nom d'appareil affiché.
- **HTTPS et port** : derrière un reverse-proxy l'API peut être en HTTPS sans le port
  `8123`. Adapter l'URL au mode d'exposition réel.

## Voir aussi

- [Docker](./docker.md) — Home Assistant Core/Container tourne souvent en conteneur.
- [Secrets & SSH](./secrets-ssh.md) — stocker `$HA_TOKEN` hors historique ; `secrets.yaml` côté HA.
- [Réseau & pfSense](./reseau-pfsense.md) — exposition réseau et reverse-proxy devant HA.
