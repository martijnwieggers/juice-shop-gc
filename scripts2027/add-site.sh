#!/usr/bin/env bash
# Voegt één nieuwe site toe, start de container en configureert NPM.
# Gebruik: bash add-site.sh [initialen]
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

# ── Invoer ────────────────────────────────────────────────────────────────────

if [[ -n "${1:-}" ]]; then
    INITIALS="${1,,}"
else
    read -rp "Initialen nieuwe student: " INITIALS
    INITIALS="${INITIALS,,}"
fi

if [[ -z "$INITIALS" ]]; then
    echo "Fout: initialen mogen niet leeg zijn." >&2
    exit 1
fi

SERVICE="juice-shop-${INITIALS}"
DOMAIN="js-${INITIALS}.wieggers.eu"

# Controleer op duplicaat
if [[ -f "$CSV" ]] && grep -q ",${SERVICE}," "$CSV"; then
    echo "Fout: ${SERVICE} bestaat al in ${CSV}." >&2
    exit 1
fi

# Detecteer NPM-netwerk (hergebruik bestaande waarde als CSV al bestaat)
if [[ -f "$CSV" ]] && [[ "$(tail -n +2 "$CSV" | grep -c '.' || true)" -gt 0 ]]; then
    NPM_NETWORK=$(tail -n +2 "$CSV" | head -1 | cut -d',' -f3)
    echo "NPM Docker-netwerk: ${NPM_NETWORK} (overgenomen uit ${CSV})"
else
    NPM_NETWORK_DEFAULT=$(docker inspect npm --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null || true)
    NPM_NETWORK_DEFAULT="${NPM_NETWORK_DEFAULT:-portainer_default}"
    read -rp "NPM Docker-netwerk (standaard: ${NPM_NETWORK_DEFAULT}): " NPM_NETWORK
    NPM_NETWORK="${NPM_NETWORK:-${NPM_NETWORK_DEFAULT}}"
fi

# ── Salts genereren en toevoegen aan CSV ──────────────────────────────────────

SALT=$(openssl rand -hex 20)
SALT_FINDIT=$(openssl rand -hex 20)
SALT_FIXIT=$(openssl rand -hex 20)

if [[ ! -f "$CSV" ]]; then
    printf 'domain,container,network,salt,salt_findit,salt_fixit\n' > "$CSV"
fi

printf '%s,%s,%s,%s,%s,%s\n' \
    "$DOMAIN" "$SERVICE" "$NPM_NETWORK" "$SALT" "$SALT_FINDIT" "$SALT_FIXIT" >> "$CSV"
echo "Toegevoegd aan ${CSV}: ${DOMAIN} → ${SERVICE}"

# ── Compose-bestand regenereren ───────────────────────────────────────────────

bash "${SCRIPT_DIR}/generate-compose.sh"

# ── Alleen de nieuwe container starten ───────────────────────────────────────

echo ""
echo "Container starten: ${SERVICE}"
docker compose -f "$OUTPUT" up -d --no-deps "$SERVICE"

# ── NPM configureren ──────────────────────────────────────────────────────────

echo ""
echo "DNS-record vereist: ${DOMAIN} → dit serveradres"
read -rp "NPM nu configureren? (j/N): " DO_NPM
if [[ "${DO_NPM,,}" != "j" ]]; then
    echo "NPM overgeslagen. Draai later: bash scripts2027/configure-npm.sh"
    exit 0
fi

read -rp "NPM e-mailadres: " NPM_EMAIL
read -rsp "NPM wachtwoord: " NPM_PASSWORD
echo ""

printf "\nVerbinden met NPM... "
TOKEN=$(npm_connect "$NPM_EMAIL" "$NPM_PASSWORD")
echo "OK"

ERRORS=0

printf "[%s] Proxy host... " "$DOMAIN"
PROXY_ID=$(npm_find_proxy "$TOKEN" "$DOMAIN")
if [[ -n "$PROXY_ID" ]]; then
    echo "bestaat al (id: ${PROXY_ID})"
else
    PROXY_ID=$(npm_create_proxy "$TOKEN" "$DOMAIN" "$SERVICE")
    if [[ -z "$PROXY_ID" ]]; then
        echo "MISLUKT"
        ERRORS=$((ERRORS + 1))
    else
        echo "aangemaakt (id: ${PROXY_ID})"
    fi
fi

if [[ "$ERRORS" -eq 0 ]]; then
    printf "[%s] Certificaat... " "$DOMAIN"
    CERT_ID=$(npm_find_cert "$TOKEN" "$DOMAIN")
    if [[ -n "$CERT_ID" ]]; then
        echo "bestaat al (id: ${CERT_ID})"
    else
        printf "aanvragen (dit kan even duren)...\n"
        CERT_ID=$(npm_create_cert "$TOKEN" "$DOMAIN")
        if [[ -z "$CERT_ID" ]]; then
            printf "[%s] Certificaat... MISLUKT\n" "$DOMAIN"
            ERRORS=$((ERRORS + 1))
        else
            printf "[%s] Certificaat... OK (id: %s)\n" "$DOMAIN" "$CERT_ID"
        fi
    fi
fi

if [[ "$ERRORS" -eq 0 ]]; then
    printf "[%s] SSL koppelen... " "$DOMAIN"
    RESULT=$(npm_enable_ssl "$TOKEN" "$PROXY_ID" "$CERT_ID" "$DOMAIN" "$SERVICE")
    if [[ -z "$RESULT" ]]; then
        echo "MISLUKT"
        ERRORS=$((ERRORS + 1))
    else
        echo "OK"
    fi
fi

echo ""
if [[ "$ERRORS" -eq 0 ]]; then
    echo "Klaar. ${DOMAIN} is actief."
else
    echo "Klaar met ${ERRORS} fout(en). Controleer de meldingen hierboven."
    exit 1
fi
