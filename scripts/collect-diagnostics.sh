#!/usr/bin/env bash

#
# Sammelt kontrolliert beschreibende Ausgaben und Logs der Pacman-Umgebung
# in einen zeitgestempelten lokalen Ordner (describe, Events, Logs,
# Argo CD Anwendungen).
#
# Das Skript verändert keinen Zustand (kein apply/scale), sondern liest
# ausschließlich den aktuellen Cluster-Zustand.
#
# Verwendung:
#   ./collect-diagnostics.sh [namespace ...]
#
# Ohne Angabe werden die Standard-Namespaces verwendet:
#   pacman-dev pacman-prod monitoring argocd
#

set -uo pipefail

DEFAULT_NAMESPACES=(pacman-dev pacman-prod monitoring argocd)
ARGOCD_NAMESPACE="argocd"

DIAG_ROOT="${DIAG_ROOT:-${HOME}/pacman-diagnostics}"
TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT_DIR="${DIAG_ROOT}/${TIMESTAMP}"

LOG_TAIL_LINES=500

show_help() {
    cat <<EOF
Verwendung:
  $0 [namespace ...]

Zweck:
  Sammelt beschreibende Ausgaben (describe, Events, Ressourcenlisten)
  und Pod-Logs für die angegebenen Namespaces (Standard:
  ${DEFAULT_NAMESPACES[*]}) sowie die Argo-CD-Anwendungen und schreibt
  sie in einen zeitgestempelten lokalen Ordner.

Ausgabeverzeichnis:
  \$DIAG_ROOT/<Zeitstempel>  (Standard-DIAG_ROOT: ${HOME}/pacman-diagnostics)

Hinweis:
  Das Skript führt keine verändernden Aktionen aus.
EOF
}

case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -*)
        echo "FEHLER: Unbekannte Option: $1" >&2
        echo "Verwende: $0 --help" >&2
        exit 2
        ;;
esac

if ! command -v kubectl >/dev/null 2>&1; then
    echo "FEHLER: kubectl wurde nicht gefunden." >&2
    exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "FEHLER: Kubernetes-Cluster ist nicht erreichbar." >&2
    exit 1
fi

if [[ $# -gt 0 ]]; then
    NAMESPACES=("$@")
else
    NAMESPACES=("${DEFAULT_NAMESPACES[@]}")
fi

if ! mkdir -p "$OUTPUT_DIR"; then
    echo "FEHLER: Zielordner '$OUTPUT_DIR' konnte nicht angelegt werden." >&2
    exit 1
fi

echo "============================================================"
echo " PACMAN DIAGNOSTICS SAMMELN"
echo "============================================================"
echo
echo "Zielordner: $OUTPUT_DIR"
echo "Namespaces: ${NAMESPACES[*]}"
echo

{
    echo "Zeitpunkt: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Kontext: $(kubectl config current-context 2>/dev/null || echo 'nicht verfügbar')"
    echo
    echo "--- kubectl version ---"
    kubectl version 2>/dev/null || true
    echo
    echo "--- Nodes ---"
    kubectl get nodes -o wide 2>/dev/null || true
} >"${OUTPUT_DIR}/cluster-overview.txt"

echo "-> cluster-overview.txt"

{
    echo "--- Argo CD Anwendungen ---"
    if kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
        kubectl get applications.argoproj.io -n "$ARGOCD_NAMESPACE" -o wide 2>/dev/null \
            || echo "Argo-CD Applications nicht verfügbar."
        echo
        echo "--- Argo CD Anwendungen (describe) ---"
        kubectl describe applications.argoproj.io -n "$ARGOCD_NAMESPACE" 2>/dev/null || true
    else
        echo "Namespace '$ARGOCD_NAMESPACE' nicht vorhanden."
    fi
} >"${OUTPUT_DIR}/argocd-applications.txt"

echo "-> argocd-applications.txt"

for namespace in "${NAMESPACES[@]}"; do
    echo
    echo "Namespace: $namespace"

    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        echo "  übersprungen (Namespace existiert nicht)"
        continue
    fi

    ns_dir="${OUTPUT_DIR}/${namespace}"
    logs_dir="${ns_dir}/logs"
    mkdir -p "$logs_dir"

    {
        echo "--- Deployments ---"
        kubectl get deployments -n "$namespace" -o wide 2>/dev/null || true
        echo
        echo "--- StatefulSets ---"
        kubectl get statefulsets -n "$namespace" -o wide 2>/dev/null || true
        echo
        echo "--- Pods ---"
        kubectl get pods -n "$namespace" -o wide 2>/dev/null || true
        echo
        echo "--- Services ---"
        kubectl get services -n "$namespace" 2>/dev/null || true
        echo
        echo "--- Ingress ---"
        kubectl get ingress -n "$namespace" 2>/dev/null || echo "Keine Ingress-Ressourcen."
        echo
        echo "--- PVC ---"
        kubectl get pvc -n "$namespace" 2>/dev/null || true
        echo
        echo "--- HPA ---"
        kubectl get hpa -n "$namespace" 2>/dev/null || echo "Keine HPA-Ressourcen."
        echo
        echo "--- Jobs ---"
        kubectl get jobs -n "$namespace" 2>/dev/null || echo "Keine Jobs."
        echo
        echo "--- CronJobs ---"
        kubectl get cronjobs -n "$namespace" 2>/dev/null || echo "Keine CronJobs."
    } >"${ns_dir}/resources.txt"
    echo "  -> ${namespace}/resources.txt"

    {
        echo "--- Events (chronologisch) ---"
        kubectl get events -n "$namespace" --sort-by='.lastTimestamp' 2>/dev/null || true
    } >"${ns_dir}/events.txt"
    echo "  -> ${namespace}/events.txt"

    {
        echo "--- Deployments (describe) ---"
        kubectl describe deployments -n "$namespace" 2>/dev/null || true
        echo
        echo "--- StatefulSets (describe) ---"
        kubectl describe statefulsets -n "$namespace" 2>/dev/null || true
        echo
        echo "--- Pods (describe) ---"
        kubectl describe pods -n "$namespace" 2>/dev/null || true
    } >"${ns_dir}/describe.txt"
    echo "  -> ${namespace}/describe.txt"

    pod_names="$(kubectl get pods -n "$namespace" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"

    for pod in $pod_names; do
        containers="$(kubectl get pod "$pod" -n "$namespace" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null || true)"

        for container in $containers; do
            kubectl logs "$pod" -n "$namespace" -c "$container" --tail="$LOG_TAIL_LINES" \
                >"${logs_dir}/${pod}_${container}.log" 2>&1 || true

            restart_count="$(
                kubectl get pod "$pod" -n "$namespace" \
                    -o jsonpath="{.status.containerStatuses[?(@.name=='${container}')].restartCount}" \
                    2>/dev/null
            )"

            if [[ -n "$restart_count" && "$restart_count" != "0" ]]; then
                kubectl logs "$pod" -n "$namespace" -c "$container" --previous --tail="$LOG_TAIL_LINES" \
                    >"${logs_dir}/${pod}_${container}_previous.log" 2>&1 || true
            fi
        done
    done
    echo "  -> ${namespace}/logs/"
done

echo
echo "============================================================"
echo " DIAGNOSTICS GESAMMELT"
echo "============================================================"
echo
echo "Ordner: $OUTPUT_DIR"
echo
find "$OUTPUT_DIR" -type f | sort

exit 0
