#!/usr/bin/env bash

#
# Erzeugt das Secret "mongodb-credentials" lokal im angegebenen Namespace.
#
# Secrets werden bewusst NICHT über Git/Kustomize verwaltet
# (siehe apps/pacman/base/secret.example.yaml).
#
# Ist das Secret bereits vorhanden, wird es standardmäßig nicht verändert.
# Eine Aktualisierung muss explizit mit --force angefordert werden.
#
# WICHTIG:
# MongoDB wertet MONGO_INITDB_ROOT_USERNAME und
# MONGO_INITDB_ROOT_PASSWORD nur bei der Initialisierung eines leeren
# Datenverzeichnisses aus. Eine Änderung des Kubernetes Secrets allein
# ändert daher nicht automatisch bereits vorhandene MongoDB-Zugangsdaten.
#
# Verwendung:
#   ./create-local-secrets.sh [namespace] [--force]
#
# Beispiele:
#   ./create-local-secrets.sh
#   ./create-local-secrets.sh pacman-prod
#   ./create-local-secrets.sh pacman-dev --force
#

set -euo pipefail

# Verhindert versehentliche Ausgabe von Befehlen einschließlich Variablenwerten.
set +x

NAMESPACE="pacman-dev"
SECRET_NAME="mongodb-credentials"
FORCE=false
NAMESPACE_SET=false

usage() {
    cat <<'EOF'
Verwendung:
  ./create-local-secrets.sh [namespace] [--force]

Optionen:
  --force       Vorhandenes Secret kontrolliert aktualisieren
  -h, --help    Hilfe anzeigen

Beispiele:
  ./create-local-secrets.sh
  ./create-local-secrets.sh pacman-prod
  ./create-local-secrets.sh pacman-dev --force
EOF
}

# Argumente auswerten
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force)
            FORCE=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --*)
            echo "Fehler: Unbekannte Option '$1'." >&2
            usage >&2
            exit 2
            ;;
        *)
            if [[ "$NAMESPACE_SET" == true ]]; then
                echo "Fehler: Es darf nur ein Namespace angegeben werden." >&2
                usage >&2
                exit 2
            fi

            NAMESPACE="$1"
            NAMESPACE_SET=true
            shift
            ;;
    esac
done

# kubectl prüfen
if ! command -v kubectl >/dev/null 2>&1; then
    echo "Fehler: kubectl wurde nicht gefunden." >&2
    exit 1
fi

# Kubernetes-Kontext prüfen
CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"

if [[ -z "$CURRENT_CONTEXT" ]]; then
    echo "Fehler: Kein aktiver Kubernetes-Kontext vorhanden." >&2
    exit 1
fi

# Namespace prüfen
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "Fehler: Namespace '$NAMESPACE' existiert nicht im aktuellen Kontext '$CURRENT_CONTEXT'." >&2
    exit 1
fi

# Vorhandenes Secret kontrolliert feststellen.
# --ignore-not-found unterscheidet einen fehlenden Secret-Namen von
# einem grundsätzlichen kubectl-/API-Fehler.
if ! EXISTING_SECRET="$(
    kubectl get secret "$SECRET_NAME" \
        -n "$NAMESPACE" \
        -o name \
        --ignore-not-found 2>/dev/null
)"; then
    echo "Fehler: Secret-Status konnte nicht geprüft werden." >&2
    exit 1
fi

if [[ -n "$EXISTING_SECRET" && "$FORCE" == false ]]; then
    echo "Secret '$SECRET_NAME' existiert bereits im Namespace '$NAMESPACE'."
    echo "Es wird nicht verändert."
    echo "Kontrollierte Aktualisierung nur mit:"
    echo "  $0 $NAMESPACE --force"
    exit 0
fi

if [[ -n "$EXISTING_SECRET" && "$FORCE" == true ]]; then
    echo "WARNUNG: Vorhandenes Secret '$SECRET_NAME' wird kontrolliert aktualisiert."
    echo "Eine Secret-Änderung allein ändert keine bereits initialisierten MongoDB-Zugangsdaten."
fi

# Zugangsdaten einlesen
read -r -p "MongoDB Root-Benutzer: " ROOT_USERNAME
read -r -s -p "MongoDB Root-Passwort: " ROOT_PASSWORD
echo

read -r -p "MongoDB Anwendungsbenutzer: " APP_USERNAME
read -r -s -p "MongoDB Anwendungspasswort: " APP_PASSWORD
echo

# Zugangsdaten bei Skriptende aus der Shell-Umgebung entfernen
cleanup() {
    unset ROOT_USERNAME ROOT_PASSWORD APP_USERNAME APP_PASSWORD 2>/dev/null || true
}

trap cleanup EXIT

# Eingaben validieren
if [[ -z "$ROOT_USERNAME" ||
      -z "$ROOT_PASSWORD" ||
      -z "$APP_USERNAME" ||
      -z "$APP_PASSWORD" ]]; then

    echo "Fehler: Benutzername und Passwort dürfen nicht leer sein." >&2
    exit 1
fi

# Manifest lokal generieren und anschließend erstellen/aktualisieren.
# Dadurch wird ein vorhandenes Secret nicht zuerst gelöscht.
kubectl create secret generic "$SECRET_NAME" \
    --namespace "$NAMESPACE" \
    --from-literal=root-username="$ROOT_USERNAME" \
    --from-literal=root-password="$ROOT_PASSWORD" \
    --from-literal=app-username="$APP_USERNAME" \
    --from-literal=app-password="$APP_PASSWORD" \
    --dry-run=client \
    -o yaml |
kubectl apply -f - >/dev/null

echo
echo "Secret '$SECRET_NAME' im Namespace '$NAMESPACE' wurde erfolgreich bereitgestellt."
echo "Die eingegebenen Zugangsdaten wurden nicht ausgegeben oder im Skript gespeichert."
echo
echo "Secret-Status prüfen mit:"
echo "  kubectl get secret $SECRET_NAME -n $NAMESPACE"