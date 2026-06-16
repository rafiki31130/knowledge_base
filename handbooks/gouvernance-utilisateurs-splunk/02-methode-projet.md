# Chapitre 2 — Méthode de projet

> La méthode de conduite d'un projet de gouvernance Splunk est aussi
> importante que ses livrables. Ce chapitre fige le cycle à quatre temps
> qui structure le projet — cadrage, maquette, audit indépendant,
> handbooks — et explique la discipline qui s'y rattache : séparation
> des rôles, monitor-only obligatoire, traçabilité des findings.

## 1. Vue d'ensemble du cycle

Pour chaque axe (RBAC, sensibilisation, WLM…), on suit le même cycle.

```mermaid
flowchart LR
    C[1 - Cadrage opérationnel<br/>doc-fondé<br/>décisions actées<br/>questions ouvertes]
    M[2 - Maquette empirique<br/>lab Splunk dédié<br/>tests unitaires<br/>findings 9.4.6]
    A[3 - Audit indépendant<br/>profil distinct<br/>rejouage SPL<br/>verdict avec ou sans correctifs]
    H[4 - Handbooks autonomes<br/>auto-suffisants<br/>SPL recopiées intégralement<br/>relus en lecture fresh]
    C --> M --> A --> H
    A -. correctifs .-> M
```

Le cycle est **itératif** : un verdict d'audit en demi-teinte renvoie en
maquette pour corrections, puis re-audit. C'est ce qui permet d'arriver à
des handbooks publiables avec un haut niveau de confiance.

## 2. Premier temps — le cadrage opérationnel

Le cadrage est un **document doc-fondé** qui prépare la maquette. Il
fixe :

- l'**objectif** de l'axe (le résultat attendu en termes opérationnels) ;
- le **périmètre** (qui, quoi, jusqu'où) ;
- les **décisions actées** (les choix de design pris en lisant la
  documentation officielle, les blogs Splunk, les retours communautaires) ;
- les **chiffrages** (paliers de quotas, parts de pool processeur, durée
  de monitor-only) ;
- les **schémas** (modèle de rôles, chaîne d'évaluation, articulation
  entre axes) ;
- les **questions ouvertes** qu'il faudra arbitrer (soit par mesure
  empirique en maquette, soit par décision humaine).

Un bon cadrage **tranche** ce qui peut l'être à partir de la
documentation et **désigne explicitement** ce qui doit être éprouvé en
maquette. Il ne mélange pas les deux.

Un mauvais cadrage est une accumulation de bonnes pratiques sans
décisions. On le reconnaît à ce qu'il dit « il faudrait probablement »
ou « selon les recommandations » sans jamais sortir un chiffre. Sortir
un chiffre, même provisoire, force la conversation. C'est la fonction
principale du cadrage.

### Format type d'un cadrage

```
1. Objectif
2. Périmètre
3. Constat fondateur (le pourquoi)
4. Synthèse opérationnelle des concepts (rappel doc)
5. Décisions actées (avec sources)
6. Questions ouvertes à arbitrer
7. Schémas (Mermaid)
8. Démarche prévue (cycle restant)
```

Le cadrage est court : 30 à 60 pages selon l'axe, pas davantage. Plus
long, il n'est plus lu.

## 3. Deuxième temps — la maquette empirique

La maquette est un **lab Splunk dédié** où l'on déploie l'ensemble des
décisions du cadrage et où l'on exécute une batterie de tests
unitaires. C'est le moment où l'on confronte la documentation à un
binaire réel.

### Lab dédié

Un lab Splunk Enterprise 9.4.6 single-instance suffit pour la grande
majorité des tests. Pour le volet indexers (chapitre 7), on ajoute un
cluster master et au moins un peer indexer.

Le lab est **isolé** (pas de connexion aux indexers de production), **à
licence trial** (60 jours suffisent largement pour un cycle), et
**reproductible** : les indices, rôles, utilisateurs et configurations
sont déployés par script depuis un dépôt versionné, jamais à la main.

### Tests unitaires

Chaque décision du cadrage devient un test. La fiche d'un test contient :

- l'**hypothèse documentée** (ce qu'on attend du comportement Splunk
  selon la doc) ;
- la **procédure** (la commande REST, la SPL, l'action UI à exécuter) ;
- le **résultat attendu** ;
- le **résultat observé** (avec le timestamp et l'identifiant du job) ;
- le **verdict** (✅ conforme, ❌ divergent, 🔍 indéterminé).

Les tests divergents — où le binaire 9.4.6 fait autre chose que ce que
dit la documentation — deviennent des **findings empiriques** que le
chapitre 4 documente.

### Pourquoi pas d'enforce direct, monitor-only obligatoire

Une discipline forte du cycle : on **ne déploie jamais une règle en
enforce** (qui bloque, qui kille, qui supprime) sans avoir d'abord
passé une phase **monitor-only** qui mesure ce que la règle ferait si
elle était appliquée.

Pour le RBAC, monitor-only se traduit en : déployer les nouveaux rôles
**à côté** des rôles legacy, ne migrer aucun utilisateur, observer la
distribution des capabilities effectives.

Pour Workload Management, monitor-only se traduit en : utiliser
`action = alert` au lieu de `action = abort` ou `action = move` — la
recherche tourne, un événement est écrit dans `_audit`, mais aucune
action de placement ou de coupure n'est appliquée.

Le délai recommandé de monitor-only est de **deux à quatre semaines
ouvrées** selon l'axe, suffisant pour capter un cycle hebdomadaire et
un cycle mensuel (clôture comptable, reporting fin de mois).

## 4. Troisième temps — l'audit indépendant

L'audit indépendant rejoue tout ou partie de la maquette avec un
**profil distinct** de celui qui l'a produite. C'est la clé de la
robustesse du cycle.

### Séparation des rôles

Une discipline forte : **l'auditeur n'est pas l'auteur**. Si la maquette
a été produite par un profil « architecte », l'audit est conduit par un
profil « sysadmin » ou « développeur » qui rejoue les SPL et la
configuration sans préjugé sur leur correction.

Pour un projet conduit par une équipe, cela se matérialise en deux
binômes distincts. Pour un projet conduit avec des agents LLM, cela se
matérialise en deux sessions distinctes, avec des briefs distincts.

### Rejouage des SPL sur le lab vivant

L'audit **rejoue chaque SPL sur le lab vivant** (pas une validation
papier). Si une SPL produit une erreur de syntaxe, si un champ
n'existe pas, si une commande est rejetée, c'est consigné dans le
rapport d'audit.

Une SPL qui « tourne » n'est pas suffisante — l'auditeur vérifie aussi
que **la sortie correspond à l'intention** de la recherche. Une SPL qui
ne renvoie aucun résultat alors qu'elle devrait en renvoyer est tout
aussi suspecte qu'une SPL en erreur.

### Verdict

L'audit rend un verdict en trois couleurs :

- **🟢 Validé** — toutes les décisions sont confirmées, toutes les SPL
  rejouées sont exploitables. Passage au handbook.
- **🟡 Anomalies mineures** — quelques SPL à corriger, une ou deux
  recommandations éditoriales. Cycle correctif court (un à deux jours),
  re-audit, passage à 🟢.
- **🟠 Anomalies majeures** — une décision structurante est invalidée,
  une partie significative des SPL ne tourne pas. Retour en cadrage
  pour reprendre la décision.

Le rapport d'audit est **public** dans le projet — il documente les
anomalies trouvées, leur sévérité, les correctifs appliqués. C'est ce
qui permet à un lecteur ultérieur de croire au handbook produit.

## 5. Quatrième temps — l'assemblage des handbooks

Les handbooks sont les **livrables d'usage** du projet. Ils synthétisent
le cadrage, la matière empirique de la maquette et les corrections
post-audit en documents **auto-suffisants** pensés pour une cible de
lecture précise.

### Auto-suffisance

Un handbook se lit **sans aucun autre document**. Il recopie
intégralement les SPL et les patterns dont son lecteur a besoin. Il
explique ses concepts sans renvoyer ailleurs (sauf pour aller plus loin
sur un sujet).

Cette **redondance est assumée**. Le coût éditorial est compensé par le
gain au moment du déploiement : l'équipe d'exploitation suit un handbook
sans naviguer dans cinq documents.

Les audits vérifient la fidélité de la recopie bloc par bloc — toute
divergence entre une SPL du handbook et la SPL d'origine de la maquette
est consignée.

### Trois angles par axe

Pour un axe donné, trois handbooks couvrent typiquement trois angles
d'entrée distincts :

- un **guide d'audit** pour le sysadmin qui hérite d'une plateforme
  sans modèle et doit décider quoi en faire ;
- un **handbook de transformation progressive** pour l'équipe qui doit
  faire passer une plateforme en production, avec phases et gates ;
- un **handbook conceptuel** pour le lecteur novice qui ne connaît pas
  la brique.

Ce guide consolide les trois angles par axe en un document unique
(chapitres 5 à 7) — pour un lecteur nouveau, la séparation des trois
angles devient une question de chapitre, pas de fichier.

## 6. Pourquoi cette discipline

Le bénéfice du cycle est triple.

**Premièrement, il évite qu'une recommandation soit déployée sur la
foi de la documentation seule sans avoir été éprouvée.** Le cas des
findings 9.4.6 (chapitre 4) montre que la documentation Splunk peut
diverger du binaire — déployer sans maquette, c'est se condamner à
découvrir l'écart en production.

**Deuxièmement, il produit des livrables traçables** où chaque
recommandation pointe sa preuve. Pour un lecteur qui découvre le
projet, c'est ce qui rend les décisions défendables : on peut toujours
remonter à la maquette qui a éprouvé la décision et au rapport d'audit
qui l'a validée.

**Troisièmement, il prépare le déploiement contextualisé.** L'équipe
d'exploitation du SHC réel n'a plus qu'à suivre un handbook pas à pas
avec ses gates de phase et ses critères de rollback. Le risque
opérationnel est contenu.

## 7. La séparation auteur / auditeur — pourquoi elle est non négociable

Une question qui revient régulièrement : « pourquoi ne pas faire
auditer le même profil qui a écrit la maquette ? ». La réponse en
quelques points.

**Un auteur a investi dans ses choix.** Il a passé du temps à
construire ses décisions ; il a un biais cognitif à les confirmer. Il
voit ce qu'il a voulu écrire, pas ce qui est écrit. C'est documenté
depuis longtemps dans la littérature sur la revue de code et la revue
éditoriale.

**Un auditeur indépendant a un mandat différent.** Son mandat est de
**trouver des écarts**. Il est récompensé pour les anomalies
détectées, pas pour la fluidité de la lecture. C'est exactement le
profil dont a besoin un livrable publiable.

**Un auditeur indépendant rejoue ce qu'il lit.** Il n'a pas la mémoire
des choix de cadrage ; il ne suit pas une SPL qu'il « se souvient »
avoir vue marcher la semaine dernière. Il la copie-colle dans le lab
et regarde ce qui sort. C'est la seule façon de détecter une SPL qui
a divergé par erreur.

## 8. Ce que la méthode produit

À la fin du cycle, pour chaque axe :

- un **cadrage opérationnel** publié avec ses décisions actées et ses
  schémas ;
- une **maquette** opérationnelle sur lab, reproductible par script,
  avec ses tests unitaires et leurs résultats ;
- un **rapport d'audit indépendant** avec son verdict et ses
  correctifs ;
- entre un et quatre **handbooks** auto-suffisants pour les profils de
  lecture identifiés.

C'est un volume éditorial significatif. Sur un projet à quatre axes,
on parle d'un corpus d'environ deux cents pages, plus la maquette et
les scripts.

Le retour sur cet investissement éditorial se matérialise au
déploiement : l'équipe d'exploitation n'a plus à inventer la conduite
du changement. Elle suit le handbook, valide chaque gate, applique le
critère de rollback documenté si nécessaire.

## 9. Adaptation au contexte du lecteur

Cette méthode n'a pas été inventée pour Splunk. Le cycle cadrage
opérationnel → maquette sur lab dédié → audit indépendant → handbooks
autonomes s'applique à n'importe quelle plateforme analytique
d'envergure, à un projet d'observabilité, à un projet de mise en
conformité d'identité, à un projet de durcissement d'un cluster
Kubernetes.

Pour un projet plus petit (par exemple un SHC à cent utilisateurs),
on peut alléger : un cadrage de vingt pages, une maquette à une demi-
journée, un audit en revue croisée d'une heure, un handbook unique
par axe. La discipline reste la même ; le volume s'ajuste.

## Sources

- [Splunk Validated Architectures](https://docs.splunk.com/Documentation/Splunk/latest/Architecture/WhatisaSplunkValidatedArchitecture)
- [Splunk Lantern — establishing a Splunk practice](https://lantern.splunk.com/)
- Code review and editorial review literature — voir par exemple Karl
  Wiegers, « Peer Reviews in Software », pour la justification empirique
  de la séparation auteur / auditeur.
