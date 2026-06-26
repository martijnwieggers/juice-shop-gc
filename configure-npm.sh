#!/usr/bin/env bash
# Stap 2: Configureert Nginx Proxy Manager via de API op basis van sites.csv.
# Draai dit nadat de containers actief zijn én DNS-records zijn ingesteld.
set -euo pipefail

CSV="sites.csv"
NPM_URL="http://127.0.0.1:81/api"

# ── Controleer vereisten ──────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
    echo "Fout: jq is vereist. Installeer met: apt install jq" >&2
    exit 1
fi

if [[ ! -f "$CSV" ]]; then
    echo "Fout: $CSV niet gevonden. Draai eerst: bash generate-compose.sh" >&2
    exit 1
fi

# ── NPM API-functies ──────────────────────────────────────────────────────────

npm_token() {
    curl -s -X POST "${NPM_URL}/tokens" \
        -H "Content-Type: application/json" \
        -d "{\"identity\":\"${1}\",\"secret\":\"${2}\"}" \
        | jq -r '.token // empty'
}

npm_find_proxy() {
    local token="$1" domain="$2"
    curl -s "${NPM_URL}/nginx/proxy-hosts" \
        -H "Authorization: Bearer ${token}" \
        | jq -r ".[] | select(.domain_names[] == \"${domain}\") | .id" | head -1
}

npm_create_proxy() {
    local token="$1" domain="$2" container="$3"
    curl -s -X POST "${NPM_URL}/nginx/proxy-hosts" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_names\": [\"${domain}\"],
            \"forward_scheme\": \"http\",
            \"forward_host\": \"${container}\",
            \"forward_port\": 3000,
            \"access_list_id\": 0,
            \"certificate_id\": 0,
            \"ssl_forced\": false,
            \"caching_enabled\": false,
            \"block_exploits\": true,
            \"allow_websocket_upgrade\": true,
            \"http2_support\": false,
            \"hsts_enabled\": false,
            \"hsts_subdomains\": false,
            \"enabled\": true,
            \"advanced_config\": \"\",
            \"locations\": [],
            \"meta\": {}
        }" | jq -r '.id // empty'
}

npm_find_cert() {
    local token="$1" domain="$2"
    curl -s "${NPM_URL}/nginx/certificates" \
        -H "Authorization: Bearer ${token}" \
        | jq -r ".[] | select(.domain_names[] == \"${domain}\") | .id" | head -1
}

npm_create_cert() {
    local token="$1" domain="$2" email="$3"
    curl -s -X POST "${NPM_URL}/nginx/certificates" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "{
            \"provider\": \"letsencrypt\",
            \"domain_names\": [\"${domain}\"],
            \"meta\": {
                \"letsencrypt_email\": \"${email}\",
                \"letsencrypt_agree\": true,
                \"dns_challenge\": false
            }
        }" | jq -r '.id // empty'
}

npm_enable_ssl() {
    local token="$1" proxy_id="$2" cert_id="$3" domain="$4" container="$5"
    curl -s -X PUT "${NPM_URL}/nginx/proxy-hosts/${proxy_id}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "{
            \"domain_names\": [\"${domain}\"],
            \"forward_scheme\": \"http\",
            \"forward_host\": \"${container}\",
            \"forward_port\": 3000,
            \"access_list_id\": 0,
            \"certificate_id\": ${cert_id},
            \"ssl_forced\": true,
            \"caching_enabled\": false,
            \"block_exploits\": true,
            \"allow_websocket_upgrade\": true,
            \"http2_support\": false,
            \"hsts_enabled\": false,
            \"hsts_subdomains\": false,
            \"enabled\": true,
            \"advanced_config\": \"\",
            \"locations\": [],
            \"meta\": {}
        }" | jq -r '.id // empty'
}

# ── Invoer ────────────────────────────────────────────────────────────────────

echo "Sites uit ${CSV}:"
tail -n +2 "$CSV" | while IFS=',' read -r domain container network; do
    echo "  - ${domain} → ${container}"
done
echo ""

read -rp "NPM e-mailadres: " NPM_EMAIL
read -rsp "NPM wachtwoord: " NPM_PASSWORD
echo ""
read -rp "Let's Encrypt e-mailadres: " LE_EMAIL

# ── Verbinden ─────────────────────────────────────────────────────────────────

printf "\nVerbinden met NPM... "
TOKEN=$(npm_token "$NPM_EMAIL" "$NPM_PASSWORD")
if [[ -z "$TOKEN" ]]; then
    echo "MISLUKT"
    echo "Fout: controleer e-mailadres en wachtwoord." >&2
    exit 1
fi
echo "OK"

# ── Configureer per site ──────────────────────────────────────────────────────

ERRORS=0

while IFS=',' read -r domain container network; do
    echo ""

    # Proxy host aanmaken of hergebruiken
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

    # Let's Encrypt certificaat aanvragen of hergebruiken
    printf "[%s] Certificaat... " "$domain"
    CERT_ID=$(npm_find_cert "$TOKEN" "$domain")
    if [[ -n "$CERT_ID" ]]; then
        echo "bestaat al (id: ${CERT_ID})"
    else
        printf "aanvragen..."
        CERT_ID=$(npm_create_cert "$TOKEN" "$domain" "$LE_EMAIL")
        if [[ -z "$CERT_ID" ]]; then
            echo " MISLUKT (DNS al actief voor ${domain}?)"
            ERRORS=$((ERRORS + 1))
            continue
        fi
        echo " OK (id: ${CERT_ID})"
    fi

    # SSL koppelen aan proxy host
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
fi
