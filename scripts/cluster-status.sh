#!/usr/bin/env bash
#
# cluster-status.sh - AP26 Betriebsautomatisierung
#
# Zeigt einen kompakten Überblick über den Zustand der Pacman-Anwendung
# und der zugehörigen Kubernetes-/Argo-CD-Ressourcen in einem Namespace.
#
# Exit Codes:
#   0 - Statusabfrage erfolgreich durchgeführt
#   1 - kubectl nicht verfügbar oder Cluster nicht erreichbar
#   2 - Aufrufparameter ungültig

set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
NAMESPACE="pacman-dev"

usage() {
  cat <<EOF
Verwendung: ${SCRIPT_NAME} [-n NAMESPACE] [-h|--help]

Zeigt den aktuellen Status der Pacman-Anwendung:
  - Argo-CD-Anwendungen
  - Deployments
  - StatefulSets
  - Pods
  - Services
  - Ingress
  - PersistentVolumeClaims
  - HorizontalPodAutoscaler
  - Jobs
  - relevante Warning-Events

Optionen:
  -n NAMESPACE   zu prüfender Namespace (Standard: ${NAMESPACE})
  -h, --help     diese Hilfe anzeigen

Exit Codes:
  0  Statusabfrage erfolgreich durchgeführt
  1  kubectl nicht verfügbar oder Cluster nicht erreichbar
  2  ungültige Aufrufparameter
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n)
      NAMESPACE="${2:-}"
      if [[ -z "${NAMESPACE}" ]]; then
        echo "Fehler: -n benötigt einen Namespace-Namen" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Fehler: unbekannter Parameter '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v kubectl >/dev/null 2>&1; then
  echo "Fehler: kubectl ist nicht installiert" >&2
  exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "Fehler: Kubernetes-Cluster nicht erreichbar" >&2
  exit 1
fi

section() {
  echo ""
  echo "=== $1 ==="
}

echo "Cluster-Status für Namespace: ${NAMESPACE}"
echo "Zeitpunkt: $(date '+%Y-%m-%d %H:%M:%S')"

section "Argo-CD-Anwendungen"
if kubectl get namespace argocd >/dev/null 2>&1; then
  kubectl get applications -n argocd 2>&1 | grep -i pacman || echo "Keine passenden Argo-CD-Anwendungen gefunden."
else
  echo "Namespace 'argocd' nicht vorhanden - übersprungen."
fi

section "Deployments"
kubectl get deployments -n "${NAMESPACE}" 2>&1 || echo "Keine Deployments gefunden."

section "StatefulSets"
kubectl get statefulsets -n "${NAMESPACE}" 2>&1 || echo "Keine StatefulSets gefunden."

section "Pods"
kubectl get pods -n "${NAMESPACE}" -o wide 2>&1 || echo "Keine Pods gefunden."

section "Services"
kubectl get services -n "${NAMESPACE}" 2>&1 || echo "Keine Services gefunden."

section "Ingress"
kubectl get ingress -n "${NAMESPACE}" 2>&1 || echo "Keine Ingress-Ressourcen gefunden."

section "PersistentVolumeClaims"
kubectl get pvc -n "${NAMESPACE}" 2>&1 || echo "Keine PVCs gefunden."

section "HorizontalPodAutoscaler"
kubectl get hpa -n "${NAMESPACE}" 2>&1 || echo "Keine HPA-Ressourcen gefunden."

section "Jobs"
kubectl get jobs -n "${NAMESPACE}" 2>&1 || echo "Keine Jobs gefunden."

section "Relevante Warning-Events (letzte 50)"
kubectl get events -n "${NAMESPACE}" --field-selector type=Warning \
  --sort-by='.lastTimestamp' 2>&1 | tail -n 50 || echo "Keine Warning-Events gefunden."

echo ""
echo "=== Cluster-Status-Abfrage abgeschlossen ==="
exit 0
