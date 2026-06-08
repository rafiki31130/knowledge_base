# Encodages à reconnaître et décoder : base64, URL, hex

Dans les logs et les charges utiles, des valeurs sont souvent **encodées** —
pour transporter des caractères spéciaux, contourner un filtre, ou simplement
par convention de protocole. Savoir **reconnaître** un encodage à l'œil avant de
le décoder fait gagner du temps et évite de mal interpréter un champ. Cette fiche
couvre les trois encodages les plus fréquents : base64, URL (percent-encoding),
hexadécimal.

> Un encodage n'est **pas** un chiffrement : il est réversible sans clé. Toute
> donnée encodée doit être traitée comme **en clair**.

Tous les exemples utilisent des chaînes inventées.

## Reconnaître à l'œil

| Indice visuel | Encodage probable |
| --- | --- |
| Lettres `A-Z a-z`, chiffres, `+ /`, finit parfois par `=` ou `==` | base64 |
| `-` et `_` à la place de `+` et `/` | base64 **url-safe** |
| Beaucoup de `%` suivis de 2 caractères hex (`%20`, `%2F`) | URL / percent-encoding |
| Uniquement `0-9 a-f` (ou `A-F`), longueur paire | hexadécimal |
| Préfixe `0x`, ou paires séparées par `:` / espaces | hex (octets) |

## Base64

Base64 encode 3 octets en 4 caractères ASCII imprimables. Reconnaissable à son
alphabet `A–Z a–z 0–9 + /` et à son **rembourrage** (`=`) en fin pour compléter
le dernier bloc.

```text
# Exemple (inventé)
dXRpbGlzYXRldXItZXhlbXBsZQ==
```

- **Longueur multiple de 4** (avec le padding `=`). Une longueur non multiple de
  4 sans padding peut indiquer une troncature ou une variante.
- **Variante url-safe** (`base64url`) : `+` → `-` et `/` → `_`, padding souvent
  omis. Fréquente dans les URL et les jetons.
- **Faux positifs** : un mot ordinaire peut « ressembler » à du base64. Le test
  fiable est de décoder et regarder si le résultat est plausible (texte lisible,
  préfixe binaire connu).

```bash
# Décoder (échantillon de log déjà extrait, valeur non sensible)
echo 'dXRpbGlzYXRldXItZXhlbXBsZQ==' | base64 -d

# Variante url-safe : remettre l'alphabet standard avant de décoder
echo 'dXRpbGlz...' | tr '_-' '/+' | base64 -d
```

## URL / percent-encoding

Le percent-encoding remplace les caractères réservés ou non-ASCII par `%` suivi
de leur code hexadécimal sur deux chiffres. Omniprésent dans les URL, les
paramètres de requête, les en-têtes.

```text
# Exemple (inventé)
chemin%2Fvers%2Fressource%3Fnom%3Duser01%26actif%3Dtrue
# décodé : chemin/vers/ressource?nom=user01&actif=true
```

- `%20` = espace, `%2F` = `/`, `%3D` = `=`, `%26` = `&`, `%3F` = `?`.
- **Double encodage** : `%252F` est `%2F` ré-encodé (`%25` = `%`). À surveiller —
  c'est un classique de contournement de filtre. Décoder **une couche à la
  fois** et observer.
- Le `+` peut représenter un espace dans les corps `application/x-www-form-urlencoded`
  (mais pas dans un chemin d'URL) : le contexte décide.

```bash
# Décoder une couche de percent-encoding (Python disponible partout)
python -c "import sys,urllib.parse as u; print(u.unquote(sys.argv[1]))" 'chemin%2Fvers%2Fressource'
```

## Hexadécimal

L'hex représente chaque octet par deux chiffres `0–9 a–f`. Sert à afficher du
binaire, des empreintes, des identifiants, des octets non imprimables.

```text
# Exemple (inventé) — "AB" en hex
4142
# Avec préfixe / séparateurs
0x4142        41:42        41 42
```

- **Longueur paire** : un octet = 2 caractères. Une longueur impaire signale une
  troncature ou un mauvais découpage.
- **Longueurs caractéristiques** : 32 caractères hex = 16 octets (souvent un
  MD5), 40 = 20 octets (SHA-1), 64 = 32 octets (SHA-256). Utile pour deviner la
  nature d'une empreinte — sans pour autant la considérer comme un secret à
  exposer.
- **Endianness** : pour des entiers, l'ordre des octets (little/big-endian)
  change la valeur. Le contexte (protocole, plateforme) tranche.

```bash
# Décoder de l'hex en texte
echo '4142' | xxd -r -p
```

## Chaînage : encodages imbriqués

Une valeur réelle combine souvent plusieurs couches (ex. base64 d'une chaîne
elle-même percent-encodée). Méthode :

1. **Identifier** la couche externe à l'œil (cf. tableau).
2. **Décoder une seule couche**.
3. **Réobserver** : le résultat est-il lisible, ou encore encodé ?
4. **Répéter** jusqu'à obtenir du contenu interprétable.

S'arrêter dès que le résultat est lisible : continuer à « décoder » du texte
clair produit du bruit.

## À retenir

- Encodage ≠ chiffrement : réversible sans clé, à traiter comme du clair.
- Reconnaître d'abord (alphabet, `%`, parité hex), décoder ensuite.
- Méfiance sur le **double encodage** (`%25...`) et les **variantes url-safe** de
  base64.
- Décoder **une couche à la fois** et réobserver.

## Voir aussi

- [Regex pour les logs : greedy, ancres, lookaround](./regex-pour-logs.md)
- [Formats de logs courants et leurs pièges de parsing](./formats-logs-et-pieges-parsing.md)
- [Identités dans les logs : SID, UPN, sAMAccountName, notions OIDC](./identites-dans-les-logs.md)
