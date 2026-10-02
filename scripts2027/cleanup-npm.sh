#!/usr/bin/env bash
# Verwijdert alle NPM proxy hosts en certificaten die in sites.csv staan.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
CSV="${ROOT}/sites.csv"

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

echo "Sites uit ${CSV}:"
tail -n +2 "$CSV" | while IFS=',' read -r domain container network _s _sf _sx; do
    echo "  - ${domain}"
done
echo ""

read -rp "NPM e-mailadres: " NPM_EMAIL
read -rsp "NPM wachtwoord: " NPM_PASSWORD
echo ""

echo ""
echo "LET OP: dit verwijdert alle proxy hosts en certificaten voor bovenstaande domeinen."
read -rp "Doorgaan? (j/N): " CONFIRM
if [[ "${CONFIRM,,}" != "j" ]]; then
    echo "Geannuleerd."
    exit 0
fi

# ── Verbinden ─────────────────────────────────────────────────────────────────

printf "\nVerbinden met NPM... "
TOKEN=$(npm_connect "$NPM_EMAIL" "$NPM_PASSWORD")
echo "OK"

# ── Verwijder per site ────────────────────────────────────────────────────────

ERRORS=0

while IFS=',' read -r domain container network _s _sf _sx; do
    echo ""

    printf "[%s] Proxy host... " "$domain"
    PROXY_ID=$(npm_find_proxy "$TOKEN" "$domain")
    if [[ -z "$PROXY_ID" ]]; then
        echo "niet gevonden"
    elif npm_delete_proxy "$TOKEN" "$PROXY_ID"; then
        echo "verwijderd (id: ${PROXY_ID})"
    else
        echo "MISLUKT"
        ERRORS=$((ERRORS + 1))
    fi

    printf "[%s] Certificaat... " "$domain"
    CERT_ID=$(npm_find_cert "$TOKEN" "$domain")
    if [[ -z "$CERT_ID" ]]; then
        echo "niet gevonden"
    elif npm_delete_cert "$TOKEN" "$CERT_ID"; then
        echo "verwijderd (id: ${CERT_ID})"
    else
        echo "MISLUKT"
        ERRORS=$((ERRORS + 1))
    fi

done < <(tail -n +2 "$CSV")

# ── Resultaat ─────────────────────────────────────────────────────────────────

echo ""
if [[ "$ERRORS" -eq 0 ]]; then
    echo "Klaar. Alles verwijderd."
else
    echo "Klaar met ${ERRORS} fout(en). Controleer de meldingen hierboven."
    exit 1
fi
