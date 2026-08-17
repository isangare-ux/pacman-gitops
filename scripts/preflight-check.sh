#!/usr/bin/env bash
#
# preflight-check.sh - AP26 Betriebsautomatisierung
#
# Prüft die Grundvoraussetzungen für den Betrieb der Pacman-Anwendung,
# bevor Cluster-Operationen (Deploy, Restore, Diagnose) durchgeführt werden.
#
# Exit Codes:
#   0 - alle Prüfungen erfolgreich
#   1 - mindestens eine Prüfung fehlgeschlagen
#   2 - Aufrufparameter ungültig

set -uo pipefail

SCRIPT_NAME="$(basename "$0")"
FAILED=0
REQUIRED_NAMESPACES=("pacman-dev" "pacman-prod" "argocd")
REQUIRED_TOOLS=("kubectl" "git" "docker" "helm" "argocd")
MIN_FREE_DISK_MB=1024

usage() {
  cat <<EOF
Verwendung: ${SCRIPT_NAME} [-h|--help]

Prüft die grundlegenden Voraussetzungen für den Betrieb der Pacman-Anwendung:
  - Docker Desktop / Docker-Daemon
  - aktueller Kubernetes-Kontext
  - Node-Status
  - benötigte Namespaces (${REQUIRED_NAMESPACES[*]})
  - freier Speicherplatz
  - Git-Status im aktuellen Repository
  - benötigte Werkzeuge (${REQUIRED_TOOLS[*]})

Exit Codes:
  0  alle Prüfungen erfolgreich
  1  mindestens eine Prüfung fehlgeschlagen
  2  ungültige Aufrufparameter
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
elif [[ $# -gt 0 ]]; then
  echo "Fehler: unbekannter Parameter '${1}'" >&2
  usage >&2
  exit 2
fi

ok()   { echo "[OK]   $*"; }
warn() { echo "[WARN] $*"; }
fail() { echo "[FAIL] $*"; FAILED=1; }

echo "=== Preflight-Check gestartet: $(date '+%Y-%m-%d %H:%M:%S') ==="

# 1. Benötigte Werkzeuge
echo "--- Werkzeuge ---"
for tool in "${REQUIRED_TOOLS[@]}"; do
  if command -v "${tool}" >/dev/null 2>&1; then
    ok "Werkzeug vorhanden: ${tool}"
  else
    fail "Werkzeug fehlt: ${tool}"
  fi
done

# 2. Docker Desktop / Docker-Daemon
echo "--- Docker ---"
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    ok "Docker-Daemon erreichbar"
  else
    fail "Docker-Daemon nicht erreichbar (läuft Docker Desktop?)"
  fi
else
  fail "docker-CLI nicht installiert"
fi

# 3. Kubernetes-Kontext
echo "--- Kubernetes-Kontext ---"
if command -v kubectl >/dev/null 2>&1; then
  CURRENT_CONTEXT="$(kubectl config current-context 2>/dev/null)"
  if [[ -n "${CURRENT_CONTEXT}" ]]; then
    ok "Aktueller Kontext: ${CURRENT_CONTEXT}"
  else
    fail "Kein aktiver Kubernetes-Kontext gesetzt"
  fi

  if kubectl cluster-info >/dev/null 2>&1; then
    ok "Cluster erreichbar"
  else
    fail "Cluster nicht erreichbar"
  fi
else
  fail "kubectl nicht installiert - Kontext-Prüfung übersprungen"
fi

# 4. Node-Status
echo "--- Node-Status ---"
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  NOT_READY="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {print $1}')"
  if [[ -z "${NOT_READY}" ]]; then
    ok "Alle Nodes im Status Ready"
  else
    fail "Nodes nicht Ready: ${NOT_READY}"
  fi
else
  warn "Node-Status kann ohne Cluster-Zugriff nicht geprüft werden"
fi

# 5. Benötigte Namespaces
echo "--- Namespaces ---"
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  for ns in "${REQUIRED_NAMESPACES[@]}"; do
    if kubectl get namespace "${ns}" >/dev/null 2>&1; then
      ok "Namespace vorhanden: ${ns}"
    else
      fail "Namespace fehlt: ${ns}"
    fi
  done
else
  warn "Namespace-Prüfung ohne Cluster-Zugriff übersprungen"
fi

# 6. Freier Speicherplatz
echo "--- Speicherplatz ---"
if command -v df >/dev/null 2>&1; then
  FREE_MB="$(df -Pm . | awk 'NR==2 {print $4}')"
  if [[ -n "${FREE_MB}" && "${FREE_MB}" =~ ^[0-9]+$ ]]; then
    if [[ "${FREE_MB}" -ge "${MIN_FREE_DISK_MB}" ]]; then
      ok "Freier Speicherplatz ausreichend: ${FREE_MB} MB"
    else
      fail "Freier Speicherplatz zu gering: ${FREE_MB} MB (Minimum ${MIN_FREE_DISK_MB} MB)"
    fi
  else
    warn "Freier Speicherplatz konnte nicht ermittelt werden"
  fi
else
  warn "df nicht verfügbar - Speicherprüfung übersprungen"
fi

# 7. Git-Status
echo "--- Git-Status ---"
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  BRANCH="$(git branch --show-current)"
  if [[ -z "$(git status --porcelain)" ]]; then
    ok "Working Tree sauber (Branch: ${BRANCH})"
  else
    warn "Working Tree hat uncommittete Änderungen (Branch: ${BRANCH})"
  fi
else
  warn "Kein Git-Repository im aktuellen Verzeichnis erkannt"
fi

echo "=== Preflight-Check beendet: $(date '+%Y-%m-%d %H:%M:%S') ==="

if [[ "${FAILED}" -eq 0 ]]; then
  echo "Ergebnis: Alle Prüfungen erfolgreich."
  exit 0
else
  echo "Ergebnis: Mindestens eine Prüfung fehlgeschlagen." >&2
  exit 1
fi