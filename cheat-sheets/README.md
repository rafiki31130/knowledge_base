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
