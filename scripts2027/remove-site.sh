#!/usr/bin/env bash
# Verwijdert één site: container, NPM-configuratie en regel in sites.csv.
# Gebruik: bash remove-site.sh [initialen]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
CSV="${ROOT}/sites.csv"
OUTPUT="${ROOT}/docker-compose-gc.yml"

# shellcheck source=_npm-lib.sh
source "${SCRIPT_DIR}/_npm-lib.sh"

if ! command -v jq &>/dev/null; then
    echo "Fout: jq is vereist. Installeer met: apt install jq" >&2
    exit 1
fi

if [[ ! -f "$CSV" ]]; then
    echo "Fout: ${CSV} niet gevonden." >&2
    exit 1
fi

# ── Invoer ────────────────────────────────────────────────────────────────────

echo "Beschikbare sites:"
tail -n +2 "$CSV" | while IFS=',' read -r domain container network _s _sf _sx; do
    echo "  - ${container} (${domain})"
done
echo ""

if [[ -n "${1:-}" ]]; then
    INITIALS="${1,,}"
else
    read -rp "Initialen te verwijderen student: " INITIALS
    INITIALS="${INITIALS,,}"
fi

if [[ -z "$INITIALS" ]]; then
    echo "Fout: initialen mogen niet leeg zijn." >&2
    exit 1
fi

SERVICE="juice-shop-${INITIALS}"
DOMAIN="js-${INITIALS}.wieggers.eu"

CSV_ROW=$(grep ",${SERVICE}," "$CSV" || true)
if [[ -z "$CSV_ROW" ]]; then
    echo "Fout: ${SERVICE} niet gevonden in ${CSV}." >&2
    exit 1
fi

echo "Te verwijderen: ${SERVICE} (${DOMAIN})"
read -rp "Doorgaan? (j/N): " CONFIRM
if [[ "${CONFIRM,,}" != "j" ]]; then
    echo "Geannuleerd."
    exit 0
fi

# ── Container stoppen en verwijderen ─────────────────────────────────────────

echo ""
printf "Container stoppen en verwijderen: %s... " "$SERVICE"
if [[ -f "$OUTPUT" ]]; then
    docker compose -f "$OUTPUT" stop "$SERVICE" 2>/dev/null || true
    docker compose -f "$OUTPUT" rm -f "$SERVICE" 2>/dev/null || true
else
    docker stop "$SERVICE" 2>/dev/null || true
    docker rm "$SERVICE" 2>/dev/null || true
fi
echo "OK"

# ── NPM-configuratie verwijderen ─────────────────────────────────────────────

read -rp "NPM-configuratie ook verwijderen? (j/N): " DO_NPM
if [[ "${DO_NPM,,}" == "j" ]]; then
    read -rp "NPM e-mailadres: " NPM_EMAIL
    read -rsp "NPM wachtwoord: " NPM_PASSWORD
    echo ""

    printf "\nVerbinden met NPM... "
    TOKEN=$(npm_connect "$NPM_EMAIL" "$NPM_PASSWORD")
    echo "OK"

    printf "[%s] Proxy host... " "$DOMAIN"
    PROXY_ID=$(npm_find_proxy "$TOKEN" "$DOMAIN")
    if [[ -z "$PROXY_ID" ]]; then
        echo "niet gevonden"
    elif npm_delete_proxy "$TOKEN" "$PROXY_ID"; then
        echo "verwijderd (id: ${PROXY_ID})"
    else
        echo "MISLUKT"
    fi

    printf "[%s] Certificaat... " "$DOMAIN"
    CERT_ID=$(npm_find_cert "$TOKEN" "$DOMAIN")
    if [[ -z "$CERT_ID" ]]; then
        echo "niet gevonden"
    elif npm_delete_cert "$TOKEN" "$CERT_ID"; then
        echo "verwijderd (id: ${CERT_ID})"
    else
        echo "MISLUKT"
    fi
fi

# ── Verwijderen uit CSV ───────────────────────────────────────────────────────

TEMP=$(mktemp)
grep -v ",${SERVICE}," "$CSV" > "$TEMP"
mv "$TEMP" "$CSV"
echo "Verwijderd uit ${CSV}: ${SERVICE}"

# ── Compose-bestand regenereren ───────────────────────────────────────────────

REMAINING=$(tail -n +2 "$CSV" | grep -c '.' || true)
if [[ "$REMAINING" -gt 0 ]]; then
    bash "${SCRIPT_DIR}/generate-compose.sh"
else
    echo "Geen sites meer over. ${OUTPUT} niet bijgewerkt."
fi

echo ""
echo "Klaar. ${SERVICE} is verwijderd."
