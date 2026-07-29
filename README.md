# Pacman GitOps

## Projektübersicht

Dieses Repository enthält sämtliche Kubernetes-Ressourcen und GitOps-Konfigurationen für die Bereitstellung der Pacman-Anwendung.

Die Konfiguration wird kontinuierlich von Argo CD überwacht und automatisch mit dem Kubernetes-Cluster synchronisiert.

---

## Struktur

```
apps/
clusters/
platform/
README.md
```

---

## Komponenten

- Kubernetes Deployments
- Services
- Ingress
- StatefulSets
- Persistent Volume Claims
- Argo CD Application
- Monitoring

---

## GitOps

Jede Änderung im Repository wird automatisch von Argo CD erkannt und auf den Kubernetes-Cluster angewendet.

---

## Lizenz

GPLv3
