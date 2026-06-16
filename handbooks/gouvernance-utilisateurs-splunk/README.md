# Gouvernance des usages Splunk — guide d'approche

> 🇬🇧 **English version available**: [`./EN/README.md`](./EN/README.md)

> Guide d'approche pour mettre en place une gouvernance complète des usages
> sur un Search Head Cluster (SHC) Splunk Enterprise de taille moyenne à
> grande (centaines à milliers d'utilisateurs). Le guide consolide une
> méthode, un modèle d'habilitation, un dispositif de sensibilisation, un
> cadre Workload Management, et un corpus de findings empiriques recueillis
> sur Splunk Enterprise 9.4.6.

## À qui ce guide s'adresse

- **Architectes Splunk** qui doivent cadrer ou refondre la gouvernance d'un
  SHC existant.
- **Sysadmins Splunk seniors** qui héritent d'une plateforme sans modèle
  documenté et doivent décider quoi en faire.
- **Chefs de projet techniques** qui pilotent une mise en conformité ou un
  durcissement d'envergure et veulent une méthode reproductible.

Prérequis implicites : vous savez ce qu'est un Search Head Cluster, vous
lisez sans peine un `authorize.conf`, vous avez déjà déployé une app
Splunk, vous comprenez ce que `srchJobsQuota` plafonne et ce qu'une saved
search est. Ce guide n'enseigne pas Splunk — il enseigne comment en
**gouverner** les usages à l'échelle.

## Ce que ce guide couvre

- **Pourquoi** un projet de gouvernance des usages est nécessaire et quels
  sont les symptômes annonciateurs (chapitre 1).
- **Comment** mener un projet de gouvernance : méthode de cadrage, maquette
  empirique, audit indépendant, handbooks (chapitre 2).
- **Quatre axes structurants** qui se combinent : durcissement des droits
  par défaut, modèle d'habilitation hybride, sensibilisation pédagogique,
  Workload Management (chapitre 3).
- **Findings empiriques 9.4.6** documentés et opposables : non-révocabilité
  d'une capability héritée, défaillance des quotas hérités, `max()`
  multi-rôles, `display_message` qui n'existe pas, ACL d'app write-sans-read
  invisible, et autres pièges (chapitre 4).
- **Guides opérationnels** par axe (chapitres 5 à 7) : audit RBAC,
  conception RBAC progressive, audit WLM, conception WLM, volet indexers.
- **Recommandations chiffrées** issues de l'état de l'art (chapitre 8).

## Ce que ce guide ne couvre pas

- L'installation et l'exploitation d'un SHC (`Distributed Deployment
  Manual` Splunk).
- L'écriture de SPL au quotidien — voir le
  [Splunk Power-User Handbook](../splunk-user-handbook/README.md) du même
  dépôt pour les bonnes pratiques côté analyste.
- Les sujets cloud, SOAR, Observability, ES, ITSI.
- Les détails d'intégration d'un IdP spécifique (ADFS, Azure AD, Okta) — on
  reste IdP-agnostique et on signale les invariants.

## Comment l'utiliser

Le guide est conçu pour être lu **séquentiellement** la première fois : la
méthode (chapitre 2) éclaire les axes (chapitre 3), qui motivent les
findings (chapitre 4), qui justifient les guides opérationnels (chapitres
5-7).

Une fois la première lecture faite, chaque chapitre se relit
indépendamment. Les chapitres 5 à 8 sont les chapitres « de référence »
qu'on rouvre au moment d'une action concrète. Le chapitre 4 (findings) est
le chapitre qu'on cite pour défendre une décision technique face à une
contre-proposition mal informée.

## Versionnage et hypothèses

Ce guide est écrit contre **Splunk Enterprise 9.4.6** on-prem, en
configuration Search Head Cluster avec indexers mutualisés. Les findings
empiriques portent l'étiquette 9.4.6 quand ils ont été observés. Si une
version mineure ultérieure de la branche 9.4 modifie un comportement
listé, le chapitre 4 le signalera.

L'archétype visé est un SHC d'environ mille utilisateurs, applications
découpées par production applicative, partageant des indexers avec
d'autres SHC. Les paliers chiffrés et les pourcentages de pool sont
calibrés pour cet archétype. À adapter au contexte — chaque
recommandation chiffrée porte la mention « à adapter au contexte ».

## Conventions

### Placeholders

Pour rester anonymisable et reproductible, le guide utilise des
placeholders cohérents d'un chapitre à l'autre.

| Catégorie | Placeholder canonique |
| --- | --- |
| Index opérationnels | `idx_<perim>` (ex. `idx_network`, `idx_security`, `idx_system`) |
| Périmètres métier | `<perim>` (ex. `network`, `security`, `system`) |
| Productions applicatives | `<prod>` (ex. `<prod>_app`, `app_<prod>`) |
| Rôles atomiques | `data_<perim>`, `feature_<cap>`, `app_<prod>`, `quota_<palier>` |
| Rôles composites | `metier_<profil>_<perim>`, `owner_app_<prod>`, `admin_iam`, `admin_ops` |
| Paliers de quotas | `quota_base`, `quota_plus`, `quota_max` |
| Pools WLM | `admin`, `scheduled`, `ad_hoc`, `bulk`, `accel` |
| Hostnames | `sh01`, `idx01`, `cm01`, `ds01` |
| Domaines | `example.com`, `corp.example.com` |
| IP / CIDR | `10.0.0.0/24`, `192.0.2.10` (RFC 5737) |
| Utilisateurs | `alice`, `bob`, `svc_app` |

Quand un exemple utilise une valeur particulière (`metier_consultatif_network`
plutôt que `metier_<profil>_<perim>`), c'est un **exemple typé** ; il
n'est pas normatif. Le pattern à retenir est la forme générique.

### Notation des recherches SPL

Les SPL sont en blocs fenced ```` ```spl ````. Les commandes shell sont en
```` ```bash ````. Les configurations Splunk sont en ```` ```ini ```` ou
```` ```conf ````.

### Citation des sources

Les affirmations factuelles pointent vers la documentation officielle
Splunk 9.4 quand elles s'en réclament. Quand une affirmation a été
**observée empiriquement sur lab 9.4.6** et qu'elle diverge de la
documentation, le chapitre 4 (findings) en porte la trace.

## Table des matières

| # | Chapitre | Objet |
| --- | --- | --- |
| 1 | [Pourquoi un projet de gouvernance](01-pourquoi-gouverner.md) | Symptômes, dérives, enjeu métier |
| 2 | [Méthode de projet](02-methode-projet.md) | Cycle cadrage → maquette → audit → handbook |
| 3 | [Les quatre axes structurants](03-quatre-axes.md) | Vue d'ensemble et articulation |
| 4 | [Findings empiriques Splunk 9.4.6](04-findings-empiriques.md) | Comportements opposables vs documentation |
| 5 | [Guide RBAC — audit, conception, déploiement](05-guide-rbac.md) | Audit, modèle hybride, paliers, SAML |
| 6 | [Guide Workload Management — search heads](06-guide-wlm-sh.md) | Pools, règles, monitor-only, enforce |
| 7 | [Guide Workload Management — indexers](07-guide-wlm-indexers.md) | Catégories `ingest`/`search_peer`, propagation cluster master |
| 8 | [Recommandations chiffrées et annexes](08-recommandations-chiffrees.md) | Paliers, pourcentages, glossaire, SPL prêtes à l'emploi |

## Sources globales

Le guide s'appuie sur la documentation officielle Splunk 9.4 :

- [Securing Splunk Enterprise 9.4 — Roles and capabilities](https://help.splunk.com/en/splunk-enterprise/administer/secure-splunk-enterprise/9.4/define-roles-on-the-splunk-platform/about-defining-roles-with-capabilities)
- [Admin Manual 9.4 — Users and roles](https://help.splunk.com/en/splunk-enterprise/administer/admin-manual/9.4/users-and-role-based-access-control)
- [authorize.conf 9.4 spec](https://help.splunk.com/en/data-management/splunk-enterprise-admin-manual/9.4/configuration-file-reference/9.4.5-configuration-file-reference/authorize.conf)
- [authentication.conf 9.4 spec](https://help.splunk.com/en/data-management/splunk-enterprise-admin-manual/9.4/configuration-file-reference/9.4.5-configuration-file-reference/authentication.conf)
- [SAML SSO 9.4](https://help.splunk.com/en/splunk-enterprise/administer/manage-users-and-security/9.4/use-saml-as-an-authentication-scheme-for-single-sign-on)
- [Manage workloads 9.4 — overview](https://help.splunk.com/en/splunk-enterprise/administer/manage-workloads/9.4/workload-management-overview)
- [Configure workload pools 9.4](https://help.splunk.com/en/splunk-enterprise/administer/manage-workloads/9.4/configure-workload-management/configure-workload-pools)
- [Configure workload rules 9.4](https://help.splunk.com/en/splunk-enterprise/administer/manage-workloads/9.4/configure-workload-management/configure-workload-rules)
- [Configure admission rules to prefilter searches 9.4](https://help.splunk.com/en/splunk-enterprise/administer/manage-workloads/9.4/configure-workload-management/configure-admission-rules-to-prefilter-searches)
- [Splunk Lantern — limit features that can impact platform performance](https://lantern.splunk.com/)
- [NIST SP 800-63B — Digital Identity Guidelines](https://pages.nist.gov/800-63-3/sp800-63b.html) (cycle de vie IAM)
