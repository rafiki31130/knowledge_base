# Concepts transverses

Connaissances utiles à plusieurs sujets, qui ne sont pas spécifiques à un
outil.

Cibles typiques :

- **Logs** : formats courants (syslog, CEF, LEEF, JSON, Windows Event, Sysmon,
  audit Linux…), champs typiques, pièges de parsing.
- **Regex** : référence rapide, pièges (greedy, anchors, lookaround).
- **Réseau** : rappels TCP/IP, DNS, TLS, HTTP, proxies — vu sous l'angle
  « qu'est-ce qu'on voit dans les logs ».
- **Time** : timezones, epoch, formats ISO, drift d'horloge.
- **Encodages** : base64, URL, hex, unicode — détection et décodage.
- **Identités** : SID, UPN, sAMAccountName, OAuth/OIDC notions de base.

Chaque fiche reste générique et publiable.

## Fiches existantes

- [Formats de logs courants et leurs pièges de parsing](./formats-logs-et-pieges-parsing.md)
- [Regex pour les logs : greedy, ancres, lookaround](./regex-pour-logs.md)
- [Temps dans les logs : timezones, epoch, drift d'horloge](./temps-dans-les-logs.md)
- [Encodages à reconnaître et décoder : base64, URL, hex](./encodages-courants.md)
- [Identités dans les logs : SID, UPN, sAMAccountName, notions OIDC](./identites-dans-les-logs.md)
- [Git : modèle mental, vocabulaire et principes (HEAD, tree, worktree, prune…)](./git-modele-mental.md)
