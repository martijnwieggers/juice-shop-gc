#!/usr/bin/env bash
# Genereert docker-compose-gc.yml met een juice-shop-gc container per site.
# Kan optioneel Nginx Proxy Manager automatisch configureren via de API.
set -euo pipefail

OUTPUT="docker-compose-gc.yml"
NPM_URL="http://127.0.0.1:81/api"

# ── NPM API-functies ──────────────────────────────────────────────────────────

npm_token() {
    curl -s -X POST "${NPM_URL}/tokens" \
        -H "Content-Type: application/json" \
        -d "{\"identity\":\"${1}\",\"secret\":\"${2}\"}" \
        | jq -r '.token // empty'
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

read -rp "Aantal sites: " NUM_SITES
if ! [[ "$NUM_SITES" =~ ^[1-9][0-9]*$ ]]; then
    echo "Fout: voer een geldig getal in." >&2
    exit 1
fi

NPM_NETWORK_DEFAULT=$(docker inspect npm --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}}{{end}}' 2>/dev/null || true)
NPM_NETWORK_DEFAULT="${NPM_NETWORK_DEFAULT:-portainer_default}"
read -rp "NPM Docker-netwerk (standaard: ${NPM_NETWORK_DEFAULT}): " NPM_NETWORK
NPM_NETWORK="${NPM_NETWORK:-${NPM_NETWORK_DEFAULT}}"

declare -a INITIALS_LIST
for ((i = 1; i <= NUM_SITES; i++)); do
    read -rp "Initialen site $i: " initials
    if [[ -z "$initials" ]]; then
        echo "Fout: initialen mogen niet leeg zijn." >&2
        exit 1
    fi
    INITIALS_LIST+=("${initials,,}")
done

echo ""
read -rp "NPM automatisch configureren via API? [j/n]: " CONFIGURE_NPM
if [[ "${CONFIGURE_NPM,,}" == "j" ]]; then
    if ! command -v jq &>/dev/null; then
        echo "Fout: jq is vereist. Installeer met: apt install jq" >&2
        exit 1
    fi
    read -rp "NPM e-mailadres: " NPM_EMAIL
    read -rsp "NPM wachtwoord: " NPM_PASSWORD
    echo ""
    read -rp "Let's Encrypt e-mailadres: " LE_EMAIL
fi

# ── Genereer docker-compose-gc.yml ────────────────────────────────────────────

{
    printf 'services:\n'

    for initials in "${INITIALS_LIST[@]}"; do
        service="juice-shop-${initials}"
        salt=$(openssl rand -hex 20)
        salt_findit=$(openssl rand -hex 20)
        salt_fixit=$(openssl rand -hex 20)

        printf '  %s:\n'                                 "$service"
        printf '    build:\n'
        printf '      context: .\n'
        printf '      dockerfile: Dockerfile\n'
        printf '    image: juice-shop-gc\n'
        printf '    container_name: %s\n'                "$service"
        printf '    restart: unless-stopped\n'
        printf '    environment:\n'
        printf '      - NODE_ENV=graafschap-college\n'
        printf '      - CONTINUE_CODE_SALT=%s\n'         "$salt"
        printf '      - CONTINUE_CODE_SALT_FINDIT=%s\n'  "$salt_findit"
        printf '      - CONTINUE_CODE_SALT_FIXIT=%s\n'   "$salt_fixit"
        printf '    networks:\n'
        printf '      - %s\n'                            "$NPM_NETWORK"
        printf '\n'
    done

    printf 'networks:\n'
    printf '  %s:\n'        "$NPM_NETWORK"
    printf '    external: true\n'

} > "$OUTPUT"

echo "Gegenereerd: $OUTPUT"

# ── NPM configureren via API ──────────────────────────────────────────────────

if [[ "${CONFIGURE_NPM,,}" == "j" ]]; then
    echo ""
    printf "Verbinden met NPM... "
    TOKEN=$(npm_token "$NPM_EMAIL" "$NPM_PASSWORD")
    if [[ -z "$TOKEN" ]]; then
        echo "MISLUKT"
        echo "Fout: kon geen token ophalen. Controleer e-mailadres en wachtwoord." >&2
        exit 1
    fi
    echo "OK"

    for initials in "${INITIALS_LIST[@]}"; do
        domain="js-${initials}.wieggers.eu"
        container="juice-shop-${initials}"

        printf "\n[%s] Proxy host aanmaken..." "$initials"
        PROXY_ID=$(npm_create_proxy "$TOKEN" "$domain" "$container")
        if [[ -z "$PROXY_ID" ]]; then
            echo " MISLUKT (bestaat mogelijk al voor ${domain})"
            continue
        fi
        echo " OK (id: ${PROXY_ID})"

        printf "[%s] Let's Encrypt certificaat aanvragen (kan even duren)..." "$initials"
        CERT_ID=$(npm_create_cert "$TOKEN" "$domain" "$LE_EMAIL")
        if [[ -z "$CERT_ID" ]]; then
            echo " MISLUKT (DNS nog niet actief voor ${domain}?)"
            continue
        fi
        echo " OK (id: ${CERT_ID})"

        printf "[%s] SSL koppelen aan proxy host..." "$initials"
        RESULT=$(npm_enable_ssl "$TOKEN" "$PROXY_ID" "$CERT_ID" "$domain" "$container")
        if [[ -z "$RESULT" ]]; then
            echo " MISLUKT"
        else
            echo " OK"
        fi
    done
fi

# ── Samenvatting ──────────────────────────────────────────────────────────────

echo ""
printf "%-10s  %-32s  %-28s  %s\n" "Site" "Subdomein" "NPM Hostname" "Port"
printf "%-10s  %-32s  %-28s  %s\n" "----------" "--------------------------------" "----------------------------" "----"
for initials in "${INITIALS_LIST[@]}"; do
    printf "%-10s  %-32s  %-28s  %s\n" \
        "$initials" \
        "js-${initials}.wieggers.eu" \
        "juice-shop-${initials}" \
        "3000"
done

echo ""
echo "Containers starten:"
echo "  docker compose -f $OUTPUT up -d"
