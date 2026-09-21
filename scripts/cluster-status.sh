#!/usr/bin/env bash

#
# Zeigt einen kompakten Gesamtstatus der Pacman-Umgebung im Cluster:
# Argo CD Anwendungen, Deployments, StatefulSets, Pods, Services,
# Ingress, PVC, HPA, Jobs und relevante Warnereignisse.
#
# Das Skript verändert keinen Zustand (kein apply/scale), sondern liest
# ausschließlich den aktuellen Cluster-Zustand.
#
# Verwendung:
#   ./cluster-status.sh [namespace ...]
#
# Ohne Angabe werden die Standard-Namespaces verwendet:
#   pacman-dev pacman-prod monitoring argocd
#

set -uo pipefail

DEFAULT_NAMESPACES=(pacman-dev pacman-prod monitoring argocd)
ARGOCD_NAMESPACE="argocd"

show_help() {
    cat <<EOF
Verwendung:
  $0 [namespace ...]

Zweck:
  Zeigt Argo CD Anwendungen, Deployments, StatefulSets, Pods, Services,
  Ingress, PVC, HPA, Jobs und relevante Warnereignisse für die
  angegebenen Namespaces (Standard: ${DEFAULT_NAMESPACES[*]}).

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

section() {
    echo
    echo "============================================================"
    echo " $*"
    echo "============================================================"
}

echo "============================================================"
echo " PACMAN CLUSTER-STATUS"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo
echo "Kontext: $(kubectl config current-context 2>/dev/null || echo 'nicht verfügbar')"
echo "Namespaces: ${NAMESPACES[*]}"

section "ARGO CD ANWENDUNGEN"
if kubectl get namespace "$ARGOCD_NAMESPACE" >/dev/null 2>&1; then
    kubectl get applications.argoproj.io -n "$ARGOCD_NAMESPACE" \
        -o custom-columns='NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' \
        2>/dev/null || echo "Argo-CD Applications nicht verfügbar."
else
    echo "Namespace '$ARGOCD_NAMESPACE' nicht vorhanden."
fi

for namespace in "${NAMESPACES[@]}"; do
    section "NAMESPACE: $namespace"

    if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
        echo "Namespace '$namespace' existiert nicht."
        continue
    fi

    echo
    echo "--- Deployments ---"
    kubectl get deployments -n "$namespace" \
        -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas' \
        2>/dev/null || true

    echo
    echo "--- StatefulSets ---"
    kubectl get statefulsets -n "$namespace" \
        -o custom-columns='NAME:.metadata.name,DESIRED:.spec.replicas,READY:.status.readyReplicas,CURRENT:.status.currentReplicas' \
        2>/dev/null || true

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
    echo "--- Jobs / CronJobs ---"
    kubectl get jobs -n "$namespace" 2>/dev/null || echo "Keine Jobs."
    kubectl get cronjobs -n "$namespace" 2>/dev/null || echo "Keine CronJobs."

    echo
    echo "--- Relevante Warnereignisse (letzte 30 Min) ---"
    WARN_EVENT_COUNT="$(
        kubectl get events -n "$namespace" \
            --field-selector type=Warning \
            --no-headers \
            2>/dev/null | wc -l
    )"

    if [[ "$WARN_EVENT_COUNT" -eq 0 ]]; then
        echo "Keine Warnereignisse."
    else
        kubectl get events -n "$namespace" \
            --field-selector type=Warning \
            --sort-by='.lastTimestamp' \
            -o custom-columns='TIME:.lastTimestamp,OBJECT:.involvedObject.name,REASON:.reason,MESSAGE:.message' \
            2>/dev/null
    fi
done

echo
echo "============================================================"
echo " CLUSTER-STATUS ENDE"
echo "============================================================"

exit 0
