# Identités dans les logs : SID, UPN, sAMAccountName, notions OIDC

Un même utilisateur apparaît dans les logs sous **plusieurs identifiants**
différents selon la source. Rapprocher ces identifiants — savoir que tel SID,
tel nom de connexion et tel sujet de jeton désignent la même personne — est un
prérequis de toute corrélation centrée sur l'identité. Cette fiche reste au
niveau des **notions** et des **formats** ; elle ne décrit aucune posture
d'authentification réelle.

> Tous les exemples sont **fictifs** : `user01`, `example.com`, `<tenant>`. Aucun
> annuaire, fournisseur d'identité ou domaine réel n'est référencé.

## Pourquoi plusieurs identifiants

Chaque système nomme l'utilisateur dans son propre référentiel : un annuaire le
connaît par un identifiant interne, un poste par un nom de session, une
application web par un sujet de jeton. Les logs héritent de ces vocabulaires.
Sans table de correspondance, trois évènements de la même personne semblent
provenir de trois entités distinctes.

## Les identifiants côté annuaire (notions)

### SID (Security Identifier)

Identifiant **binaire/numérique** d'un principal de sécurité (utilisateur,
groupe, machine). Format générique :

```text
S-1-5-21-<domaine>-<rid>
```

- Stable : il **ne change pas** quand on renomme le compte. C'est le pivot le
  plus fiable côté annuaire.
- La partie finale (`RID`, *relative identifier*) distingue le principal au sein
  d'un même domaine. Certains RID sont **bien connus** (génériques, non liés à un
  environnement) : par convention, le RID `500` désigne le compte administrateur
  intégré, `501` le compte invité.
- Dans les logs : préférer corréler par SID plutôt que par nom, car le nom est
  mutable.

### sAMAccountName

Nom de connexion **court**, hérité des systèmes plus anciens.

```text
user01
```

- Court (longueur historiquement limitée), unique au sein d'un domaine.
- **Mutable** : un renommage de compte le change → mauvais pivot pour de la
  corrélation longue durée.

### UPN (User Principal Name)

Identifiant de connexion en **forme d'adresse e-mail**, plus moderne.

```text
user01@example.com
```

- Lisible, souvent aligné sur l'adresse mail, mais **pas garanti** identique à
  celle-ci.
- Mutable lui aussi (changement de nom, de suffixe).

### Tableau comparatif

| Identifiant | Forme | Stable au renommage ? | Bon pivot ? |
| --- | --- | --- | --- |
| SID | `S-1-5-21-...-<rid>` | oui | oui (référence) |
| sAMAccountName | `user01` | non | corrélation courte seulement |
| UPN | `user01@example.com` | non | lisible, à recouper |

## Côté applicatif : notions OIDC

OIDC (OpenID Connect) est une couche d'identité **standardisée** au-dessus de
OAuth 2.x. Les applications web modernes y reçoivent l'identité de l'utilisateur
sous forme de **revendications** (*claims*) dans un jeton. Au niveau **notions**,
les claims utiles pour rapprocher une identité sont :

| Claim | Sens | Remarque |
| --- | --- | --- |
| `sub` | *subject* : identifiant **stable** de l'utilisateur chez l'émetteur | Le pivot fiable côté OIDC (opaque, ne pas tenter d'y lire un nom) |
| `iss` | *issuer* : qui a émis le jeton | Identifie le référentiel d'émission |
| `preferred_username` | nom d'affichage de connexion | Pratique mais **mutable** |
| `email` | adresse mail revendiquée | À recouper, pas une preuve d'identité à elle seule |

Points de prudence :

- `sub` est **opaque** : c'est un identifiant, pas un nom lisible. Le corréler tel
  quel, sans chercher à le « décoder ».
- `email` et `preferred_username` sont **mutables** et parfois non vérifiés selon
  la configuration de l'émetteur : utiliser `sub` (+ `iss`) comme clé stable.
- Cette fiche décrit la **sémantique des claims** du standard, pas un déploiement
  particulier — aucun fournisseur ni `<tenant>` réel n'est impliqué.

## Rapprocher les identités (méthode)

L'objectif : une **table de correspondance** qui relie les identifiants d'une même
personne entre référentiels.

1. **Choisir un pivot stable par référentiel** : SID côté annuaire, `sub` (+
   `iss`) côté OIDC.
2. **Recouper par attributs lisibles** (UPN ↔ `email`, sAMAccountName ↔
   `preferred_username`) en gardant à l'esprit qu'ils sont **mutables**.
3. **Matérialiser la correspondance** dans une table de référence
   (`<identite_canonique>` ← {SID, UPN, sAMAccountName, sub}).
4. **Normaliser à la lecture** : ramener chaque évènement à l'identité canonique
   avant d'agréger ou de pivoter.

```text
# Table de correspondance (forme générique, valeurs fictives)
identite_canonique | sid                  | sam     | upn                 | sub
-------------------|----------------------|---------|---------------------|------------
user01             | S-1-5-21-...-1108    | user01  | user01@example.com  | <sub_opaque>
```

## Pièges

- **Corréler par nom mutable** (sAMAccountName, UPN, `preferred_username`) : un
  renommage casse silencieusement l'historique. Préférer un pivot stable.
- **Confondre identité humaine et compte de service/machine** : un SID peut
  désigner une machine ou un service, pas une personne. Vérifier le type de
  principal.
- **Sensibilité à la casse** : les noms de connexion sont souvent
  insensibles à la casse côté annuaire mais comparés de façon sensible dans une
  requête. Normaliser (`lower(...)`) avant de joindre.

## À retenir

- Un utilisateur = plusieurs identifiants selon la source ; corréler exige une
  table de correspondance.
- Pivots **stables** : SID (annuaire), `sub`+`iss` (OIDC). Pivots **mutables** à
  recouper seulement : sAMAccountName, UPN, `email`.
- Normaliser chaque évènement vers une identité canonique avant d'agréger.

## Voir aussi

- [Encodages à reconnaître et décoder : base64, URL, hex](./encodages-courants.md)
- [Formats de logs courants et leurs pièges de parsing](./formats-logs-et-pieges-parsing.md)
- [Pivots classiques : user → host → process → network → file](../methodologies/pivots-investigation.md)
