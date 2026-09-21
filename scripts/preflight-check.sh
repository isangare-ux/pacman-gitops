#!/usr/bin/env bash

#
# Prüft, ob die lokale Arbeitsumgebung für den Betrieb der Pacman-Umgebung
# bereit ist: Docker Desktop, Kubernetes-Kontext, Node-Status, erforderliche
# Namespaces, freier Speicher, Git-Status und benötigte Werkzeuge.
#
# Das Skript verändert keinen Zustand (kein apply/scale), sondern meldet
# ausschließlich Befunde.
#
# Verwendung:
#   ./preflight-check.sh
#

set -uo pipefail

EXPECTED_CONTEXT="docker-desktop"

REQUIRED_NAMESPACES=(pacman-dev pacman-prod monitoring argocd)
REQUIRED_TOOLS=(docker kubectl git)

MIN_FREE_DISK_GB=5

ERROR_COUNT=0

error() {
    echo "FEHLER: $*" >&2
    ERROR_COUNT=$((ERROR_COUNT + 1))
}

warning() {
    echo "WARNUNG: $*" >&2
}

ok() {
    echo "OK: $*"
}

show_help() {
    cat <<EOF
Verwendung:
  $0

Zweck:
  Prüft Docker Desktop, Kubernetes-Kontext, Node-Status, erforderliche
  Namespaces, freien Speicher, Git-Status und benötigte Werkzeuge, bevor
  die Pacman-Umgebung betrieben wird.

Hinweis:
  Das Skript führt keine verändernden Aktionen aus.
EOF
}

case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    "")
        ;;
    *)
        echo "FEHLER: Unbekannter Parameter: $1"
        echo "Verwende: $0 --help"
        exit 2
        ;;
esac

echo "============================================================"
echo " PACMAN PREFLIGHT-CHECK"
echo "============================================================"

echo
echo "[1/7] Benötigte Werkzeuge prüfen ..."

for tool in "${REQUIRED_TOOLS[@]}"; do
    if command -v "$tool" >/dev/null 2>&1; then
        ok "Werkzeug '$tool' ist verfügbar."
    else
        error "Werkzeug '$tool' wurde nicht gefunden."
    fi
done

echo
echo "[2/7] Docker Desktop prüfen ..."

if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        ok "Docker Desktop läuft."
    else
        error "Docker Desktop ist nicht erreichbar. Bitte Docker Desktop starten."
    fi
else
    error "Docker ist nicht installiert, Docker-Desktop-Prüfung wird übersprungen."
fi

echo
echo "[3/7] Kubernetes-Kontext prüfen ..."

if command -v kubectl >/dev/null 2>&1; then
    CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

    if [[ -z "$CURRENT_CONTEXT" ]]; then
        error "Kein Kubernetes-Kontext aktiv."
    elif [[ "$CURRENT_CONTEXT" != "$EXPECTED_CONTEXT" ]]; then
        error "Aktueller Kubernetes-Kontext: '$CURRENT_CONTEXT' (erwartet: '$EXPECTED_CONTEXT')."
    else
        ok "Kubernetes-Kontext: $CURRENT_CONTEXT"
    fi
else
    error "kubectl ist nicht installiert, Kontext-Prüfung wird übersprungen."
fi

echo
echo "[4/7] Node-Status prüfen ..."

if command -v kubectl >/dev/null 2>&1; then
    if ! kubectl get nodes >/dev/null 2>&1; then
        error "Kubernetes-Cluster ist nicht erreichbar."
    else
        NOT_READY_NODES="$(
            kubectl get nodes --no-headers 2>/dev/null \
                | awk '$2 != "Ready" {print $1}'
        )"

        if [[ -z "$NOT_READY_NODES" ]]; then
            ok "Alle Nodes sind im Status 'Ready'."
        else
            error "Nodes nicht im Status 'Ready': $NOT_READY_NODES"
        fi

        kubectl get nodes
    fi
else
    error "kubectl ist nicht installiert, Node-Status-Prüfung wird übersprungen."
fi

echo
echo "[5/7] Erforderliche Namespaces prüfen ..."

if command -v kubectl >/dev/null 2>&1; then
    for namespace in "${REQUIRED_NAMESPACES[@]}"; do
        if kubectl get namespace "$namespace" >/dev/null 2>&1; then
            ok "Namespace '$namespace' vorhanden."
        else
            error "Namespace '$namespace' fehlt."
        fi
    done
else
    error "kubectl ist nicht installiert, Namespace-Prüfung wird übersprungen."
fi

echo
echo "[6/7] Freien Speicher prüfen ..."

FREE_DISK_KB="$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')"

if [[ -n "$FREE_DISK_KB" ]]; then
    FREE_DISK_GB=$((FREE_DISK_KB / 1024 / 1024))

    if (( FREE_DISK_GB < MIN_FREE_DISK_GB )); then
        warning "Nur ${FREE_DISK_GB} GiB freier Speicher verfügbar (empfohlen: >= ${MIN_FREE_DISK_GB} GiB)."
    else
        ok "${FREE_DISK_GB} GiB freier Speicher verfügbar."
    fi
else
    warning "Freier Speicher konnte nicht ermittelt werden."
fi

echo
echo "[7/7] Git-Status prüfen ..."

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if command -v git >/dev/null 2>&1 && git -C "$REPO_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    CURRENT_BRANCH="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unbekannt')"
    ok "Git-Branch: $CURRENT_BRANCH"

    if [[ -n "$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null)" ]]; then
        warning "Es gibt unversionierte oder nicht committete Änderungen im Repository."
        git -C "$REPO_ROOT" status --short
    else
        ok "Arbeitsverzeichnis ist sauber, keine offenen Änderungen."
    fi
else
    warning "Kein Git-Repository gefunden oder git ist nicht installiert."
fi

echo
echo "============================================================"

if (( ERROR_COUNT > 0 )); then
    echo " PREFLIGHT-CHECK FEHLGESCHLAGEN ($ERROR_COUNT Fehler)"
    echo "============================================================"
    exit 1
fi

echo " PREFLIGHT-CHECK ERFOLGREICH"
echo "============================================================"
exit 0
