---
title: Réseau & pfSense
category: cheat-sheets
tags: [reseau, pfsense, diagnostic, vlan, tcpdump, cheat-sheet]
created: 2026-06-08
---

# Réseau & pfSense — Cheat-sheet

## À quoi ça sert

Boîte à outils de diagnostic réseau (Linux) plus les commandes propres au pare-feu
pfSense (basé sur FreeBSD/pf). On y revient dès qu'une connexion ne passe pas :
vérifier une IP/route, voir ce qui écoute, résoudre un nom, capturer du trafic,
ou inspecter les règles et états du pare-feu en console quand l'interface web n'aide pas.

## Commandes de base

### Diagnostic réseau (Linux)

```bash
ip a                                 # adresses IP de toutes les interfaces
ip a show <iface>                    # adresses d'une interface précise
ip r                                 # table de routage (route par défaut incluse)
ip r get 10.0.0.10                   # quelle route serait empruntée pour une dest.
ip -br a                             # vue condensée (1 ligne par interface)
ip link set <iface> up               # activer une interface
```

```bash
ss -tlnp                             # ports TCP en écoute + processus (t=tcp l=listen n=numérique p=pid)
ss -ulnp                             # idem en UDP
ss -tnp                              # connexions TCP établies + processus
ss -s                                # statistiques globales des sockets
```

```bash
ping -c 4 10.0.0.1                   # 4 paquets ICMP vers une cible
ping -c 4 -I <iface> 10.0.0.1        # forcer l'interface source
traceroute 10.0.0.1                  # chemin réseau saut par saut (UDP)
traceroute -I 10.0.0.1               # variante ICMP
mtr 10.0.0.1                         # traceroute + ping en continu (interactif)
```

```bash
dig example.com                      # résolution DNS (enregistrement A par défaut)
dig example.com AAAA                 # enregistrement IPv6
dig example.com MX +short            # MX, sortie minimale
dig @<serveur_dns> example.com       # interroger un résolveur précis
dig -x 10.0.0.1                      # résolution inverse (PTR)
```

```bash
# Capture de trafic (tcpdump) — exécuter avec privilèges
tcpdump -ni <iface> host 10.0.0.1            # tout le trafic avec un hôte (n=pas de DNS)
tcpdump -ni <iface> port 443                 # trafic sur un port
tcpdump -ni <iface> 'tcp port 443 and host 10.0.0.1'
tcpdump -ni <iface> -w /tmp/capture.pcap     # écrire dans un fichier (analyse Wireshark)
tcpdump -nr /tmp/capture.pcap                # relire un fichier de capture
```

### Notions VLAN

```bash
# Sous-interface taguée VLAN sous Linux (802.1Q)
ip link add link <iface> name <iface>.<id> type vlan id <id>
ip link set <iface>.<id> up
ip a show <iface>.<id>
```

- Un VLAN segmente logiquement un même lien physique ; nommage usuel `vlan<id>`.
- Port *access* = un seul VLAN, trafic non tagué ; port *trunk* = plusieurs VLAN tagués.
- Côté Proxmox/Linux, un trunk arrive sur une interface et se décline en `<iface>.<id>`.

### pfSense (console / shell)

```bash
pfctl -s rules                       # règles de filtrage chargées
pfctl -s nat                         # règles NAT (redirections, masquerade)
pfctl -s states                      # table des états (connexions suivies)
pfctl -s info                        # statistiques globales du pare-feu
pfctl -s all                         # tout afficher
```

```bash
# Recharger un fichier de règles (pfSense gère normalement ça via la GUI)
pfctl -f /etc/pf.conf                # recharger la conf pf
pfctl -n -f /etc/pf.conf             # tester la conf sans l'appliquer (dry-run)
```

```bash
# Rejouer des actions pfSense scriptées (PHP playback)
pfSsh.php playback enableallowallwan   # ex : règle de secours « allow all » sur le WAN
pfSsh.php playback                      # lister les scripts playback disponibles
```

- Le menu console pfSense (numéroté) couvre l'essentiel : option *Set interface(s) IP
  address*, *Reset webConfigurator password*, *Restart webConfigurator*, *Ping host*.

## Pièges fréquents

- **Oublier `-n`** : `ss`, `tcpdump`, `traceroute` font de la résolution DNS par défaut,
  ce qui ralentit et peut masquer le problème. `-n` affiche les IP brutes.
- **Capturer sur la mauvaise interface** : sur un trunk, le trafic d'un VLAN est sur
  `<iface>.<id>`, pas sur `<iface>` brute. Vérifier avec `ip -br a` avant de capturer.
- **`ping` qui échoue ≠ panne réseau** : ICMP est souvent bloqué par un pare-feu alors
  que TCP/443 passe. Tester le vrai port (`ss`, `tcpdump`, ou un client applicatif).
- **Confondre route et règle de pare-feu** : un paquet routé peut être *droppé* par pf.
  Vérifier `ip r` (acheminement) ET `pfctl -s rules` / `pfctl -s states` (filtrage).
- **Modifier `/etc/pf.conf` à la main sur pfSense** : la conf est régénérée depuis la GUI
  à chaque sauvegarde ; les éditions manuelles sont écrasées. Passer par la GUI/playback.
- **VLAN non tagué côté switch** : si le port n'est pas en trunk pour le VLAN voulu, la
  sous-interface `<iface>.<id>` ne verra aucun trafic. Vérifier la config du switch.

## Voir aussi

- [Proxmox VE](./proxmox.md) — réseau des VM/CT et bridges sur l'hyperviseur
- [HAProxy & TLS](./haproxy-tls.md) — répartition de charge et terminaison TLS en amont
- [Linux & systemd](./linux-systemd.md) — services réseau et résolution locale
