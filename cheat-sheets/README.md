# Cheat-sheets

Aide-mémoires techniques : les commandes essentielles d'une techno (les 20 % qui
servent 80 % du temps), avec valeurs en placeholders et pièges fréquents. Contenu
générique et anonymisé — aucune référence à une infrastructure réelle.

## Format des fiches

Chaque fiche suit la même structure :

1. **À quoi ça sert** — rôle de la techno, quand on la touche.
2. **Commandes de base** — l'essentiel, en blocs annotés et commentés, valeurs en placeholders.
3. **Pièges fréquents** — erreurs classiques et le réflexe correct.
4. **Voir aussi** — liens vers les fiches connexes.

## Fiches

- [Git](./git.md) — versionnage : config, branches, rebase, annulation, enchaînements courants.
- [Proxmox VE](./proxmox.md) — VM (`qm`), conteneurs LXC (`pct`), stockage, sauvegardes `vzdump`.
- [Réseau & pfSense](./reseau-pfsense.md) — diagnostic réseau (`ip`, `ss`, `dig`, `tcpdump`), VLAN, `pfctl`.
- [HAProxy & TLS](./haproxy-tls.md) — reverse-proxy (frontend/backend/ACL), reload, inspection TLS `openssl`.
- [Docker](./docker.md) — conteneurs et Docker Compose : exploitation, logs, volumes, nettoyage.
- [Linux & systemd](./linux-systemd.md) — services (`systemctl`), logs (`journalctl`), diagnostic système, `apt`.
- [Stockage & NAS](./stockage-nas.md) — Samba/CIFS, NFS, `lsblk`/`blkid`, `fstab`, sauvegarde `rsync`/`tar`.
- [Bases de données](./bases-de-donnees.md) — CouchDB via HTTP (`curl`, Fauxton), MongoDB (`mongosh`, `mongodump`).
- [Ansible](./ansible.md) — `ansible-playbook`, ad-hoc, `ansible-vault`, `ansible-galaxy`.
- [GitHub CLI (gh)](./gh-cli.md) — auth, `gh repo/pr/issue/run`, `gh api` (git lui-même → [git.md](./git.md)).
- [Secrets & SSH](./secrets-ssh.md) — 1Password CLI `op`, clés SSH, `~/.ssh/config`, agent, tunnels, `scp`/`sftp`.
- [Splunk (administration / CLI)](./splunk-admin.md) — CLI admin `splunk` : start/stop, `btool`, `search`, index, `_internal` (SPL → [splunk/](../splunk/README.md)).
- [Splunk — knowledge bundle (réplication classique)](./splunk-knowledge-bundle-classique.md) — fiche réflexe incident : fondamentaux, pré-requis (snapshot + `confOp` SHC), points de contrôle par symptôme. Disponible aussi en anglais : [`EN/splunk-knowledge-bundle-classic.md`](./EN/splunk-knowledge-bundle-classic.md).
- [Splunk RBAC (rôles & héritage)](./splunk-rbac.md) — `authorize.conf` : rôles built-in, stanza `[default]` (plancher), héritage par type de droit, retrait d'une capability via `<cap> = disabled` (précédence de conf), `POST`=SET destructif, cascade `DELETE`.
- [NetBox (API REST)](./netbox-api.md) — API `curl` (`dcim`, `ipam`), filtres/pagination, client `pynetbox`.
- [Home Assistant (CLI & API)](./home-assistant.md) — CLI `ha`, `check_config`, API REST `/api/states` & `/api/services`, reload YAML.
- [Claude Code & MCP](./claude-code-mcp.md) — CLI `claude`, config `mcpServers` (stdio/http), debug MCP (`tools/list`).
- [Stack média conteneurisée](./stack-media.md) — patterns conteneurs, `qbittorrent-nox`, API *arr (`X-Api-Key`), VPN gluetun (Docker → [docker.md](./docker.md)).
- [Mermaid dans Obsidian](./mermaid-obsidian.md) — diagrammes en texte : flowchart/sequence/state/ER, liens internes, thème, portabilité GitHub/Forgejo.
