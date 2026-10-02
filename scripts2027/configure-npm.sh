#!/usr/bin/env bash
# Configureert Nginx Proxy Manager voor alle sites in sites.csv.
# Idempotent: bestaande proxy hosts en certificaten worden overgeslagen.
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
    echo "Fout: ${CSV} niet gevonden. Voeg eerst een site toe met: bash scripts2027/add-site.sh" >&2
    exit 1
fi

# ── Invoer ────────────────────────────────────────────────────────────────────

echo "Sites uit ${CSV}:"
tail -n +2 "$CSV" | while IFS=',' read -r domain container network _s _sf _sx; do
    echo "  - ${domain} → ${container}"
done
echo ""

read -rp "NPM e-mailadres: " NPM_EMAIL
read -rsp "NPM wachtwoord: " NPM_PASSWORD
echo ""

# ── Verbinden ─────────────────────────────────────────────────────────────────

printf "\nVerbinden met NPM... "
TOKEN=$(npm_connect "$NPM_EMAIL" "$NPM_PASSWORD")
echo "OK"

# ── Configureer per site ──────────────────────────────────────────────────────

ERRORS=0

while IFS=',' read -r domain container network _s _sf _sx; do
    echo ""

    printf "[%s] Proxy host... " "$domain"
    PROXY_ID=$(npm_find_proxy "$TOKEN" "$domain")
    if [[ -n "$PROXY_ID" ]]; then
        echo "bestaat al (id: ${PROXY_ID})"
    else
        PROXY_ID=$(npm_create_proxy "$TOKEN" "$domain" "$container")
        if [[ -z "$PROXY_ID" ]]; then
            echo "MISLUKT — site overgeslagen"
            ERRORS=$((ERRORS + 1))
            continue
        fi
        echo "aangemaakt (id: ${PROXY_ID})"
    fi

    printf "[%s] Certificaat... " "$domain"
    CERT_ID=$(npm_find_cert "$TOKEN" "$domain")
    if [[ -n "$CERT_ID" ]]; then
        echo "bestaat al (id: ${CERT_ID})"
    else
        printf "aanvragen (dit kan even duren)...\n"
        CERT_ID=$(npm_create_cert "$TOKEN" "$domain")
        if [[ -z "$CERT_ID" ]]; then
            printf "[%s] Certificaat... MISLUKT\n" "$domain"
            ERRORS=$((ERRORS + 1))
            continue
        fi
        printf "[%s] Certificaat... OK (id: %s)\n" "$domain" "$CERT_ID"
    fi

    printf "[%s] SSL koppelen... " "$domain"
    RESULT=$(npm_enable_ssl "$TOKEN" "$PROXY_ID" "$CERT_ID" "$domain" "$container")
    if [[ -z "$RESULT" ]]; then
        echo "MISLUKT"
        ERRORS=$((ERRORS + 1))
    else
        echo "OK"
    fi

done < <(tail -n +2 "$CSV")

# ── Resultaat ─────────────────────────────────────────────────────────────────

echo ""
if [[ "$ERRORS" -eq 0 ]]; then
    echo "Klaar. Alle sites zijn geconfigureerd."
else
    echo "Klaar met ${ERRORS} fout(en). Controleer de meldingen hierboven."
    echo "Draai het script opnieuw nadat DNS en containers correct zijn — al geconfigureerde sites worden overgeslagen."
    exit 1
fi
