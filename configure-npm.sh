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

# ── NPM API-helper ────────────────────────────────────────────────────────────
# Voert een curl-request uit en geeft de volledige response terug.
# Bij HTTP-fout (4xx/5xx) wordt de foutmelding naar stderr geschreven.

npm_api() {
    local method="$1" token="$2" path="$3" body="${4:-}"
    local args=(-s -w "\n%{http_code}" -X "$method" "${NPM_URL}${path}"
                -H "Authorization: Bearer ${token}")

    [[ -n "$body" ]] && args+=(-H "Content-Type: application/json" -d "$body")

    local raw http_code response
    raw=$(curl "${args[@]}")
    http_code=$(printf '%s' "$raw" | tail -1)
    response=$(printf '%s' "$raw" | head -n -1)

    if [[ ! "$http_code" =~ ^2 ]]; then
        local msg
        msg=$(printf '%s' "$response" | jq -r '.error.message // .message // .' 2>/dev/null || printf '%s' "$response")
        printf '  [HTTP %s] %s\n' "$http_code" "$msg" >&2
    fi

    printf '%s' "$response"
}

# ── NPM API-functies ──────────────────────────────────────────────────────────

npm_token() {
    local response id
    response=$(curl -s -w "\n%{http_code}" -X POST "${NPM_URL}/tokens" \
        -H "Content-Type: application/json" \
        -d "{\"identity\":\"${1}\",\"secret\":\"${2}\"}")
    local http_code body
    http_code=$(printf '%s' "$response" | tail -1)
    body=$(printf '%s' "$response" | head -n -1)
    if [[ ! "$http_code" =~ ^2 ]]; then
        printf '  [HTTP %s] %s\n' "$http_code" \
            "$(printf '%s' "$body" | jq -r '.error.message // .message // .' 2>/dev/null || printf '%s' "$body")" >&2
    fi
    printf '%s' "$body" | jq -r '.token // empty'
}

npm_find_proxy() {
    local token="$1" domain="$2"
    npm_api GET "$token" "/nginx/proxy-hosts" \
        | jq -r ".[] | select(.domain_names[] == \"${domain}\") | .id" 2>/dev/null | head -1 || true
}

npm_create_proxy() {
    local token="$1" domain="$2" container="$3"
    local response id
    response=$(npm_api POST "$token" "/nginx/proxy-hosts" "{
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
    }")
    id=$(printf '%s' "$response" | jq -r '.id // empty' 2>/dev/null || true)
    if [[ -z "$id" ]]; then
        printf '  NPM: %s\n' \
            "$(printf '%s' "$response" | jq -r '.error.message // .message // .' 2>/dev/null || printf '%s' "$response")" >&2
    fi
    printf '%s' "$id"
}

npm_find_cert() {
    local token="$1" domain="$2"
    npm_api GET "$token" "/nginx/certificates" \
        | jq -r ".[] | select(.domain_names[] == \"${domain}\") | .id" 2>/dev/null | head -1 || true
}

npm_create_cert() {
    local token="$1" domain="$2" email="$3"
    local response id
    response=$(npm_api POST "$token" "/nginx/certificates" "{
        \"provider\": \"letsencrypt\",
        \"domain_names\": [\"${domain}\"],
        \"meta\": {
            \"letsencrypt_email\": \"${email}\",
            \"letsencrypt_agree\": true
        }
    }")
    id=$(printf '%s' "$response" | jq -r '.id // empty' 2>/dev/null || true)
    if [[ -z "$id" ]]; then
        printf '  NPM: %s\n' \
            "$(printf '%s' "$response" | jq -r '.error.message // .message // .' 2>/dev/null || printf '%s' "$response")" >&2
    fi
    printf '%s' "$id"
}

npm_enable_ssl() {
    local token="$1" proxy_id="$2" cert_id="$3" domain="$4" container="$5"
    local response id
    response=$(npm_api PUT "$token" "/nginx/proxy-hosts/${proxy_id}" "{
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
    }")
    id=$(printf '%s' "$response" | jq -r '.id // empty' 2>/dev/null || true)
    if [[ -z "$id" ]]; then
        printf '  NPM: %s\n' \
            "$(printf '%s' "$response" | jq -r '.error.message // .message // .' 2>/dev/null || printf '%s' "$response")" >&2
    fi
    printf '%s' "$id"
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
        printf "aanvragen (dit kan even duren)...\n"
        CERT_ID=$(npm_create_cert "$TOKEN" "$domain" "$LE_EMAIL")
        if [[ -z "$CERT_ID" ]]; then
            printf "[%s] Certificaat... MISLUKT\n" "$domain"
            ERRORS=$((ERRORS + 1))
            continue
        fi
        printf "[%s] Certificaat... OK (id: %s)\n" "$domain" "$CERT_ID"
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
