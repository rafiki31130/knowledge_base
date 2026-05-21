# Parsing phase : ce qui s'exécute où

Distinction entre Universal Forwarder (UF) et Heavy Forwarder (HF) / indexer
concernant le traitement des événements. Source de bugs récurrents quand on
configure `props.conf` au mauvais endroit.

## Sur un UF (sans `force_local_processing`)

Seuls deux paramètres de `props.conf` sont actifs nativement :

- `EVENT_BREAKER_ENABLE`
- `EVENT_BREAKER`

Tout le reste appartient à la **parsing phase**, qui s'exécute sur le HF ou
l'indexer.

## Ce qui ne s'exécute PAS sur un UF (contrairement à une idée répandue)

- `TIME_FORMAT`, `TIME_PREFIX`, `DATETIME_CONFIG`, `MAX_TIMESTAMP_LOOKAHEAD`
  → parsing phase.
- `TRUNCATE` → parsing phase.
- `LINE_BREAKER`, `SHOULD_LINEMERGE` → parsing phase.
- `KV_MODE`, `TRANSFORMS-*`, `EXTRACT-*` → parsing ou search-time.

Le **timestamp est donc posé par le HF ou l'indexer**, pas par le UF.
Configurer `TIME_FORMAT` sur un UF sans `force_local_processing` n'a aucun
effet.

## `force_local_processing`

Déplace la parsing phase sur le UF. Coût CPU significatif. À réserver aux cas
où :

- pas de HF disponible entre UF et indexer, **et**
- la précision du timestamp (ou un autre paramètre de parsing) est critique
  au plus près de la source.
