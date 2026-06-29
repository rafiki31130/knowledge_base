# Gouvernance du changement ITIL (Change Enablement) et pratiques associées

Cette fiche couvre la gestion du changement ITIL **dans sa version complète**
(types de changements, CAB, RFC, RACI, fenêtres de gel, revue post-implémentation)
et la **situe** parmi les autres pratiques ITIL (incident, problème, niveaux de
service, mise en production, amélioration continue). Objectif : disposer du
vocabulaire et de l'appareil de gouvernance tel qu'attendu en entreprise, puis
savoir le **dégrader proprement** quand le contexte est plus léger.

Modèle de documentation/CMDB associé : [itil-modele-documentation.md](./itil-modele-documentation.md).

## Change Enablement (ex-Change Management)

ITIL 4 a renommé *Change Management* en **Change Enablement** pour insister sur
l'objectif — **permettre le changement en maîtrisant le risque**, pas le bloquer.
Finalité : maximiser le nombre de changements réussis en évaluant correctement
les risques, en autorisant, et en gérant le calendrier.

### Les trois types de changement

C'est l'outil de **proportionnalité** central : on adapte la cérémonie au risque.

| Type | Définition | Autorisation | Exemple |
|---|---|---|---|
| **Standard** | pré-approuvé, répétable, à faible risque, suit une procédure connue | **aucune approbation par changement** — la procédure *est* l'approbation | exécuter un script de déploiement validé, créer un compte standard |
| **Normal** | doit être évalué, autorisé et planifié individuellement | selon le niveau de risque (voir *change authority*) | nouvelle version applicative, modification d'architecture |
| **Emergency** | doit être implémenté au plus vite (incident majeur, sécurité) | **ECAB** (CAB d'urgence), procédure accélérée ; documentation *a posteriori* | correctif de faille critique, contournement d'une panne majeure |

Erreur classique : traiter tout changement comme « normal ». Bien classer les
**standards** (et constituer leur catalogue) évite une bureaucratie inutile.

### Le change record / RFC

Toute demande de changement « normal » donne lieu à un enregistrement —
historiquement une **RFC** (Request for Change), aujourd'hui un *change record*.
Il porte au minimum :

- **Description et justification** (le *pourquoi*) ;
- **Périmètre et CI impactés** (lien vers la CMDB) ;
- **Évaluation du risque et de l'impact** (souvent une matrice probabilité ×
  impact) ;
- **Plan d'implémentation** et **plan de retour arrière** (*back-out*) ;
- **Plan de test / critères de succès** ;
- **Fenêtre planifiée** et ressources ;
- **Autorité d'approbation** et trace de la décision.

### CAB, ECAB et autorité de changement

- **CAB** (Change Advisory Board) : comité qui **conseille** sur l'évaluation et
  l'autorisation des changements normaux (et revoit le calendrier). Il *conseille*
  — l'autorité formelle reste le *change manager* / l'autorité désignée.
- **ECAB** (Emergency CAB) : formation réduite et rapide pour les changements
  d'urgence.
- **Change authority** : l'autorisation est **déléguée par niveau de risque** —
  un changement à faible risque peut être approuvé par un responsable d'équipe ;
  un changement majeur remonte à un comité de direction. ITIL 4 pousse à
  **décentraliser** l'autorité au plus près de l'équipe quand c'est possible
  (éviter le CAB goulot d'étranglement).

### Calendrier et fenêtres de gel

- **Change Schedule** (anciennement *Forward Schedule of Changes*) : calendrier
  partagé des changements à venir — sert à détecter les conflits.
- **Change freeze / blackout window** : périodes où les changements non urgents
  sont **interdits** (clôture comptable, pics d'activité, gel de fin d'année).

### RACI

La gouvernance d'entreprise formalise les rôles via une matrice **RACI** :

| Lettre | Rôle |
|---|---|
| **R** — Responsible | exécute la tâche |
| **A** — Accountable | rend des comptes, **décide** (un seul par activité) |
| **C** — Consulted | consulté avant décision (dialogue) |
| **I** — Informed | informé après décision |

Appliquée au changement : qui *rédige* la RFC (R), qui *autorise* (A), qui est
*consulté* (sécurité, métier — C), qui est *informé* (exploitation, support — I).

### Après le changement : PIR

La **PIR** (Post-Implementation Review) vérifie, après coup, que le changement a
atteint son objectif, sans effet de bord, et que le *back-out* n'a pas été
nécessaire. Les enseignements alimentent l'amélioration continue.

```text
   RFC ─► évaluation risque ─► autorisation (CAB / authority)
    │                                   │
    └──────────► calendrier ◄───────────┘
                     │
            implémentation (+ plan de back-out)
                     │
              revue post-implémentation (PIR) ─► CSI
```

## Situer le changement dans ITIL 4

### Le Service Value System (SVS)

ITIL 4 organise tout autour du **SVS** : comment les composants de
l'organisation collaborent pour créer de la valeur. Pièces maîtresses :

- **Les 7 principes directeurs** : *focus sur la valeur ; partir de l'existant ;
  progresser itérativement avec du feedback ; collaborer et rendre visible ;
  penser et travailler de façon holistique ; rester simple et pratique ;
  optimiser et automatiser.* (Le « rester simple » justifie de dégrader l'appareil
  quand il n'apporte pas de valeur.)
- **La Service Value Chain** : six activités — *Plan, Improve, Engage, Design &
  Transition, Obtain/Build, Deliver & Support* — combinées en *value streams*.
- **Les 4 dimensions** : *organisations & personnes ; information & technologie ;
  partenaires & fournisseurs ; flux de valeur & processus.* À considérer pour tout
  service (un écosystème ne se réduit pas à sa technique).

### Pratiques voisines à connaître

| Pratique | Rôle | Point clé |
|---|---|---|
| **Incident Management** | restaurer le service au plus vite | priorité = **impact × urgence** ; objectif = rétablissement, pas cause racine |
| **Problem Management** | trouver la **cause racine** d'incidents récurrents | produit des **erreurs connues** (→ KEDB) et déclenche des changements correctifs |
| **Service Request Management** | traiter les demandes standard des utilisateurs | s'appuie souvent sur des **changements standards** pré-approuvés |
| **Service Level Management** | définir et suivre les niveaux de service | **SLA** (avec le client), **OLA** (entre équipes internes), **UC** (*underpinning contract*, avec un fournisseur) |
| **Release Management** | planifier la **mise à disposition** d'une version | distinct du déploiement technique ; gère le *quoi/quand* livré |
| **Deployment Management** | **déployer** techniquement vers les environnements | s'appuie sur la **DML** |
| **Service Configuration Mgmt** | maintenir le modèle des CI (CMDB) | cf. [itil-modele-documentation.md](./itil-modele-documentation.md) |
| **Continual Service Improvement (CSI)** | améliorer en continu | *CSI register* ; modèle en 7 étapes ; la PIR l'alimente |

Distinguer **Incident / Problème / Erreur connue / Changement** est fondamental :
un *incident* est une interruption ; un *problème* est sa cause sous-jacente ; une
*erreur connue* est un problème dont la cause et le contournement sont documentés
(KEDB) ; un *changement* est l'action de modification (souvent la résolution
définitive du problème). Confondre incident et problème conduit à « rouvrir »
sans cesse les mêmes incidents.

## Dégrader proprement : du complet au *lean*

L'appareil complet est dimensionné pour des organisations à fort risque et
multi-équipes. Dans un contexte plus léger (petite équipe, voire mono-opérateur),
on **conserve la valeur** (traçabilité, réversibilité, contrôle proportionné) et
on **allège la cérémonie** :

| Élément entreprise | Équivalent *lean* |
|---|---|
| CAB / ECAB | la personne (ou le pair) qui valide ; pas de comité |
| RFC formelle | un ticket léger / une *issue* / le message de commit + le plan |
| RACI | implicite — une seule personne ou un duo |
| Change Schedule | l'historique git + un journal daté |
| Fenêtre de gel | bon sens (éviter de déployer un vendredi soir) |
| PIR | une note de clôture : objectif atteint ? effets de bord ? |
| KEDB | un dossier « pièges connus » (cause + contournement) |
| DML | les dépôts git |

Ce qu'on **ne sacrifie jamais**, même *lean* : savoir *quoi* a changé, *pourquoi*,
*par qui*, avec un **plan de retour arrière** et une **trace auditable**. C'est
exactement ce que fournissent git + des étapes de validation + un journal — la
typologie standard/normal/emergency restant la règle de proportionnalité.

## À retenir

- **Change Enablement** *active* le changement en maîtrisant le risque ; sa
  typologie **standard / normal / emergency** dose la cérémonie.
- L'appareil entreprise : **RFC**, **CAB/ECAB**, **change authority** par niveau de
  risque, **calendrier + gels**, **RACI**, **plan de back-out**, **PIR**.
- Le changement s'inscrit dans le **SVS** d'ITIL 4 et dialogue avec
  **incident / problème / niveaux de service / mise en production / CSI**.
- Savoir **distinguer** incident, problème, erreur connue et changement.
- En contexte léger : garder la **valeur** (traçabilité, réversibilité), alléger la
  **cérémonie**. *Rester simple et pratique* est un principe directeur ITIL, pas une
  entorse.