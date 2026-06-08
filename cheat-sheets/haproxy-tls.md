---
title: HAProxy & TLS
category: cheat-sheets
tags: [haproxy, tls, ssl, openssl, reverse-proxy, cheat-sheet]
created: 2026-06-08
---

# HAProxy & TLS — Cheat-sheet

## À quoi ça sert

HAProxy est un répartiteur de charge / reverse-proxy TCP et HTTP : il reçoit les
connexions sur des *frontends*, applique des règles (ACL) et les distribue vers des
*backends*. Il termine souvent le TLS. On y touche pour publier un service, valider
une config avant rechargement, recharger sans coupure, et diagnostiquer côté certificat
avec `openssl` (chaîne, dates, SAN, EKU).

## Commandes de base

### Structure d'une configuration HAProxy

```haproxy
# /etc/haproxy/haproxy.cfg — squelette type

frontend fe_https
    bind *:443 ssl crt /etc/haproxy/certs/example.com.pem   # PEM = clé + cert + chaîne
    mode http
    acl is_app hdr(host) -i app.example.com   # ACL sur l'en-tête Host
    use_backend be_app if is_app              # routage conditionnel
    default_backend be_default

backend be_app
    mode http
    balance roundrobin                        # algo de répartition
    option httpchk GET /health                # check de santé HTTP
    server app1 10.0.0.11:8080 check          # check = surveillance active
    server app2 10.0.0.12:8080 check
```

### Validation et rechargement

```bash
haproxy -c -f /etc/haproxy/haproxy.cfg        # vérifier la syntaxe (check) AVANT reload
haproxy -vv                                    # version + options de compilation

# Rechargement à chaud via systemd (recommandé : pas de coupure des connexions)
systemctl reload haproxy                        # recharge la conf sans tuer les sessions
systemctl restart haproxy                       # redémarre (coupe les connexions en cours)
```

### Stats socket (runtime API)

```bash
# Suppose 'stats socket /run/haproxy/admin.sock mode 660 level admin' dans la conf
echo "show info" | socat stdio /run/haproxy/admin.sock      # infos process
echo "show stat" | socat stdio /run/haproxy/admin.sock      # stats CSV (front/back/serveurs)
echo "show servers state" | socat stdio /run/haproxy/admin.sock

# Mettre un serveur en maintenance / le réactiver sans recharger la conf
echo "disable server be_app/app1" | socat stdio /run/haproxy/admin.sock
echo "enable server be_app/app1"  | socat stdio /run/haproxy/admin.sock
```

### Inspection TLS avec OpenSSL

```bash
# Se connecter et voir la chaîne présentée par le serveur
openssl s_client -connect example.com:443 -servername example.com   # SNI via -servername
openssl s_client -connect example.com:443 -servername example.com -showcerts   # toute la chaîne

# Récupérer le certificat serveur et l'inspecter
openssl s_client -connect example.com:443 -servername example.com </dev/null 2>/dev/null \
  | openssl x509 -noout -text                       # détail complet du certificat
```

```bash
# Inspecter un certificat depuis un fichier
openssl x509 -in cert.pem -noout -text              # tout le contenu
openssl x509 -in cert.pem -noout -dates             # dates notBefore / notAfter
openssl x509 -in cert.pem -noout -subject -issuer   # sujet et émetteur
openssl x509 -in cert.pem -noout -ext subjectAltName       # SAN (noms couverts)
openssl x509 -in cert.pem -noout -ext extendedKeyUsage     # EKU (ex : serverAuth)

# Vérifier qu'une clé et un certificat correspondent (mêmes modulus)
openssl x509 -in cert.pem -noout -modulus | openssl md5
openssl rsa  -in key.pem  -noout -modulus | openssl md5     # les deux md5 doivent coïncider
```

### Notions ACME (Let's Encrypt et compatibles)

- ACME automatise l'émission et le renouvellement de certificats via un challenge
  (`http-01` sur le port 80, `dns-01` via un enregistrement TXT, `tls-alpn-01`).
- Clients courants : `certbot`, `acme.sh`, ou l'intégration native du reverse-proxy.
- HAProxy attend un PEM unique (`clé privée` + `certificat` + `chaîne intermédiaire`)
  par hôte ; après renouvellement, recharger HAProxy (`systemctl reload haproxy`).

## Pièges fréquents

- **Recharger sans `haproxy -c` d'abord** : une conf invalide fait échouer le reload et
  peut laisser le service arrêté. Toujours valider la syntaxe avant.
- **PEM mal assemblé** : HAProxy veut clé + cert + intermédiaires concaténés dans un seul
  fichier. Oublier la chaîne intermédiaire = erreurs « unable to verify » chez les clients.
- **Oublier `-servername` avec `s_client`** : sans SNI, le serveur renvoie le certificat
  par défaut, pas celui de l'hôte visé — diagnostic faussé sur un proxy multi-domaines.
- **`restart` au lieu de `reload`** : `restart` coupe les connexions établies ; pour une
  simple mise à jour de conf ou de certificat, `reload` suffit et évite la coupure.
- **SAN manquant** : les navigateurs ignorent le `Common Name` ; le nom doit figurer dans
  le `subjectAltName`. Vérifier avec `openssl x509 -ext subjectAltName`.
- **Certificat expiré non détecté** : surveiller `notAfter` (`-dates`) ; un renouvellement
  ACME réussi mais sans reload HAProxy sert toujours l'ancien certificat.

## Voir aussi

- [Réseau & pfSense](./reseau-pfsense.md) — diagnostic de connectivité en amont du proxy
- [Docker](./docker.md) — backends souvent conteneurisés derrière HAProxy
- [Linux & systemd](./linux-systemd.md) — gérer le service haproxy et lire ses logs
