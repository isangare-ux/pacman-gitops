#!/usr/bin/env bash
#
# collect-diagnostics.sh - AP26 Betriebsautomatisierung
#
# Sammelt kontrolliert beschreibende Ausgaben und Logs der Pacman-Anwendung
# in einem lokalen, zeitgestempelten Diagnoseordner. Es werden ausschließlich
# beschreibende Kubernetes-Ausgaben (describe/get/logs) gesammelt - keine
# Secret-Werte, Tokens, Passwörter oder vollständige kubeconfig-Inhalte.
#
# Exit Codes:
#   0 - Diagnosedaten erfolgreich gesammelt
#   1 - kubectl nicht verfügbar oder Cluster nicht erreichbar
#   2 - Aufrufparameter ungültig

set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
NAMESPACE="pacman-dev"
OUTPUT_ROOT="./diagnostics"

usage() {
  cat <<EOF
Verwendung: ${SCRIPT_NAME} [-n NAMESPACE] [-o OUTPUT_ROOT] [-h|--help]

Sammelt beschreibende Diagnoseinformationen der Pacman-Anwendung in einem
zeitgestempelten Unterordner von OUTPUT_ROOT (Standard: ${OUTPUT_ROOT}):
  - kubectl get/describe für Deployments, StatefulSets, Pods, Services,
    Ingress, PVC, HPA, Jobs
  - Pod-Logs (aktuell und ggf. vorheriger Container-Start)
  - relevante Events

Es werden keine Secret-Werte, Tokens, Passwörter oder vollständige
kubeconfig-Inhalte gesammelt oder ausgegeben.

Optionen:
  -n NAMESPACE     zu prüfender Namespace (Standard: ${NAMESPACE})
  -o OUTPUT_ROOT    Basisverzeichnis für Diagnoseordner (Standard: ${OUTPUT_ROOT})
  -h, --help        diese Hilfe anzeigen

Exit Codes:
  0  Diagnosedaten erfolgreich gesammelt
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
    -o)
      OUTPUT_ROOT="${2:-}"
      if [[ -z "${OUTPUT_ROOT}" ]]; then
        echo "Fehler: -o benötigt ein Zielverzeichnis" >&2
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

TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
TARGET_DIR="${OUTPUT_ROOT}/${TIMESTAMP}"

if ! mkdir -p "${TARGET_DIR}"; then
  echo "Fehler: Diagnoseordner konnte nicht angelegt werden: ${TARGET_DIR}" >&2
  exit 1
fi

echo "Sammle Diagnosedaten für Namespace '${NAMESPACE}' in: ${TARGET_DIR}"

{
  echo "Diagnose-Zeitpunkt (UTC): ${TIMESTAMP}"
  echo "Namespace: ${NAMESPACE}"
  echo "Kontext: $(kubectl config current-context 2>/dev/null)"
} > "${TARGET_DIR}/metadata.txt"

RESOURCE_TYPES=("deployments" "statefulsets" "pods" "services" "ingress" "pvc" "hpa" "jobs")

for res in "${RESOURCE_TYPES[@]}"; do
  echo "Sammle Übersicht: ${res}"
  kubectl get "${res}" -n "${NAMESPACE}" -o wide > "${TARGET_DIR}/get-${res}.txt" 2>&1

  echo "Sammle Details (describe): ${res}"
  kubectl describe "${res}" -n "${NAMESPACE}" > "${TARGET_DIR}/describe-${res}.txt" 2>&1
done

echo "Sammle Events"
kubectl get events -n "${NAMESPACE}" --sort-by='.lastTimestamp' \
  > "${TARGET_DIR}/events.txt" 2>&1

echo "Sammle Pod-Logs"
mkdir -p "${TARGET_DIR}/logs"
POD_NAMES="$(kubectl get pods -n "${NAMESPACE}" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)"
if [[ -n "${POD_NAMES}" ]]; then
  for pod in ${POD_NAMES}; do
    kubectl logs "${pod}" -n "${NAMESPACE}" --all-containers=true \
      > "${TARGET_DIR}/logs/${pod}.log" 2>&1
    kubectl logs "${pod}" -n "${NAMESPACE}" --all-containers=true --previous \
      > "${TARGET_DIR}/logs/${pod}.previous.log" 2>/dev/null || true
  done
else
  echo "Keine Pods gefunden - keine Logs gesammelt." > "${TARGET_DIR}/logs/README.txt"
fi

echo "Diagnosedaten vollständig gesammelt unter: ${TARGET_DIR}"
exit 0
