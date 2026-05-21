# Patrons de CI/CD pour déploiement Splunk

Patterns récurrents et limites pour automatiser la livraison de
configurations Splunk (apps, props/transforms, savedsearches…).

## Pattern « GitOps artisanal »

```
Git (un repo par app)  →  Jenkins (trigger sur master)  →  Ansible (playbooks par tier)
```

Fonctionne, mais limites structurelles fréquentes :

- L'état de déploiement n'existe nulle part de façon canonique — il est
  inféré depuis Git, depuis l'API Splunk, depuis les logs de pipeline.
- Pas de validation pre-deploy (pas de `btool check` automatique).
- Pas de visibilité « actif vs en queue ».
- Pas de détection de drift.

### Améliorations minimales

- **Validation statique** : `btool check` en pre-deploy.
- **Diff structuré** versionné en artifact de build.
- **Queue formalisée** (ex. `queue.json` avec TTL et statuts).
- **Assertions post-deploy** via API REST Splunk.
- **Audit trail** : index interne alimenté via HEC.

## Orchestration unifiée

### AWX (Ansible Automation Platform open source)

Résout nativement :

- Workflow Templates multi-étapes avec gates d'approbation humaine.
- Queue de jobs native avec priorité.
- RBAC sur le déclenchement.
- Audit trail requêtable.
- API REST complète.

### XL Deploy + XL Release (Digital.ai)

Réponse enterprise :

- **XLR** orchestre la release avec gates et approbations.
- **XLD** fournit un modèle déclaratif avec tracking d'état par environnement
  et détection de drift.
- Requiert le développement de types custom Splunk en XML / Jython
  (`synthetic.xml` + scripts de déploiement par tier). Effort de mise en
  place non négligeable.

### Limitation commune

Aucune plateforme générique ne connaît le modèle de données Splunk. La
**détection de drift** reste à construire : jobs périodiques qui interrogent
l'API REST Splunk et comparent à l'état Git.
