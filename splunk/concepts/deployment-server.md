# Deployment Server

Distribution centralisée de configurations vers des forwarders (UF/HF). Le
mécanisme et ses contraintes opérationnelles.

## Mécanique de distribution

Le Deployment Server (DS) **ne pousse pas** — il attend. Les forwarders
interrogent le DS toutes les 60 s par défaut (`phoneHomeIntervalInSecs` dans
`deploymentclient.conf`). À chaque poll, le DS compare les hashes des app
bundles présents sous `deployment-apps/` avec ce que le client a déclaré au
poll précédent. En cas de divergence, le client télécharge le delta.

## Contraintes opérationnelles

- **Un seul DS actif par pool de clients.** Deux DS qui revendiquent les mêmes
  clients = split-brain de configuration (l'app gagnante dépend du dernier
  poll).
- **Ne jamais éditer `etc/apps/`** sur un UF géré par DS : le prochain poll
  écrase sans avertissement. Les modifications locales se perdent.
- **Les apps doivent vivre sous `deployment-apps/`** sur le DS, pas sous
  `etc/apps/` — sinon elles ne sont pas distribuées.

## Ciblage des clients — `serverclass.conf`

Filtres disponibles pour assigner un client à une serverclass :

- `whitelist` / `blacklist` (FQDN, IP, glob).
- `clientName` (valeur déclarée dans `deploymentclient.conf` du client).
- `machineTypesFilter` (OS / architecture).
- `tagValues` (tags assignés dynamiquement).

**Ordre de priorité en cas de conflit : `blacklist` > `whitelist`.** Un client
blacklisté est exclu même s'il matche un whitelist plus spécifique.
