---
title: NetBox (API REST)
category: cheat-sheets
tags: [netbox, api, rest, dcim, ipam, pynetbox, cheat-sheet]
created: 2026-06-08
---

# NetBox (API REST) — Cheat-sheet

## À quoi ça sert

NetBox est une source de vérité pour l'infrastructure (équipements, IP, racks, câblage).
Son **API REST** permet d'automatiser la lecture et l'écriture de cet inventaire :
récupérer la liste des équipements, chercher une adresse IP, créer une interface, etc.
Cette fiche couvre l'API directe en `curl` et le client Python officiel `pynetbox`.

L'API attend un **jeton** dans l'en-tête `Authorization: Token <token>`, qu'on garde
dans une variable d'environnement (`$NETBOX_TOKEN`) plutôt qu'en clair. Base d'URL type :
`https://netbox.example.com/api/`.

## Commandes de base

### Authentification et appel `curl`

```bash
# En-têtes communs : jeton + Accept JSON (réutilisés ci-dessous)
curl -s -H "Authorization: Token $NETBOX_TOKEN" \
     -H "Accept: application/json; indent=4" \
     "https://netbox.example.com/api/dcim/devices/"
```

### Lecture — endpoints courants

```bash
# Équipements (DCIM)
curl -s -H "Authorization: Token $NETBOX_TOKEN" \
     "https://netbox.example.com/api/dcim/devices/"

# Une ressource précise par ID
curl -s -H "Authorization: Token $NETBOX_TOKEN" \
     "https://netbox.example.com/api/dcim/devices/<id>/"

# Adresses IP (IPAM)
curl -s -H "Authorization: Token $NETBOX_TOKEN" \
     "https://netbox.example.com/api/ipam/ip-addresses/"

# Interfaces (DCIM)
curl -s -H "Authorization: Token $NETBOX_TOKEN" \
     "https://netbox.example.com/api/dcim/interfaces/"
```

### Filtres et pagination

```bash
# Filtre par champ (querystring). Filtres cumulables avec &
curl -s -H "Authorization: Token $NETBOX_TOKEN" \
     "https://netbox.example.com/api/dcim/devices/?name=<nom>&status=active"

# Filtre par interface d'un équipement
curl -s -H "Authorization: Token $NETBOX_TOKEN" \
     "https://netbox.example.com/api/dcim/interfaces/?device=<nom>"

# Pagination : limit = taille de page, offset = décalage
curl -s -H "Authorization: Token $NETBOX_TOKEN" \
     "https://netbox.example.com/api/ipam/ip-addresses/?limit=50&offset=100"

# Tout récupérer en une fois (limit=0 = pas de pagination, à manier avec prudence)
curl -s -H "Authorization: Token $NETBOX_TOKEN" \
     "https://netbox.example.com/api/dcim/devices/?limit=0"

# Recherche plein-texte transverse à un endpoint
curl -s -H "Authorization: Token $NETBOX_TOKEN" \
     "https://netbox.example.com/api/dcim/devices/?q=<terme>"
```

La réponse paginée a la forme `{ "count": N, "next": "<url>", "previous": null, "results": [...] }` ;
suivre `next` jusqu'à `null` pour parcourir toutes les pages.

### Écriture — `POST` / `PATCH` / `DELETE`

```bash
# Créer une ressource (POST) : Content-Type JSON + corps
curl -s -X POST \
     -H "Authorization: Token $NETBOX_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"name": "<nom>", "device_type": <id>, "site": <id>, "status": "active"}' \
     "https://netbox.example.com/api/dcim/devices/"

# Modifier partiellement une ressource (PATCH)
curl -s -X PATCH \
     -H "Authorization: Token $NETBOX_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"status": "offline"}' \
     "https://netbox.example.com/api/dcim/devices/<id>/"

# Supprimer (DELETE)
curl -s -X DELETE \
     -H "Authorization: Token $NETBOX_TOKEN" \
     "https://netbox.example.com/api/dcim/devices/<id>/"
```

### Client Python — `pynetbox`

```python
import pynetbox

# Connexion (le jeton vient de l'environnement, pas du code)
import os
nb = pynetbox.api("https://netbox.example.com", token=os.environ["NETBOX_TOKEN"])

# Lire
devices = nb.dcim.devices.all()                 # tous les équipements (itérable)
dev = nb.dcim.devices.get(<id>)                 # un par ID
dev = nb.dcim.devices.get(name="<nom>")         # un par filtre unique
matches = nb.dcim.devices.filter(status="active", site="<slug>")   # plusieurs

# Créer
nb.dcim.interfaces.create(device=<id>, name="<nom>", type="1000base-t")

# Modifier un objet récupéré
dev.status = "offline"
dev.save()

# Supprimer
dev.delete()
```

## Pièges fréquents

- **Jeton en clair** : ne jamais coder le token dans un script ni le passer en argument
  visible. Le lire depuis `$NETBOX_TOKEN` / variable d'environnement.
- **Slash final obligatoire** : les endpoints NetBox attendent un `/` final
  (`/api/dcim/devices/`). Sans lui, on récupère souvent une redirection ou une erreur.
- **Oublier la pagination** : par défaut l'API ne renvoie qu'une page (champ `next`).
  Boucler sur `next`, ou utiliser `pynetbox` dont `.all()` pagine automatiquement.
- **`limit=0` sur un gros endpoint** : ramène tout d'un coup ; lourd pour le serveur et le
  client sur un inventaire volumineux. Préférer une pagination raisonnable.
- **Confondre ID et slug** : certains champs liés attendent un **ID numérique** (clé
  étrangère), d'autres un **slug** selon l'endpoint/version. Vérifier la forme attendue.
- **`get()` qui lève une exception** : `pynetbox` `get()` échoue si le filtre renvoie
  plusieurs objets ; utiliser `filter()` quand le résultat peut être multiple.
- **Droits du jeton** : un token peut être en lecture seule. Un `POST`/`PATCH` qui renvoie
  403 vient souvent des permissions du token, pas de la requête.

## Voir aussi

- [Réseau & pfSense](./reseau-pfsense.md) — données réseau qu'on documente dans l'IPAM NetBox.
- [Secrets & SSH](./secrets-ssh.md) — stocker `$NETBOX_TOKEN` hors du code et de l'historique.
- [GitHub CLI (gh)](./gh-cli.md) — autre exemple d'API REST piloté en `gh api`/`curl`.
