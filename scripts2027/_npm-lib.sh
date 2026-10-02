#!/usr/bin/env bash
# Gedeelde NPM API-hulpfuncties — source dit bestand, voer het niet uit.

NPM_URL="http://127.0.0.1:81/api"

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

npm_token() {
    local raw http_code body
    raw=$(curl -s -w "\n%{http_code}" -X POST "${NPM_URL}/tokens" \
        -H "Content-Type: application/json" \
        -d "{\"identity\":\"${1}\",\"secret\":\"${2}\"}")
    http_code=$(printf '%s' "$raw" | tail -1)
    body=$(printf '%s' "$raw" | head -n -1)
    if [[ ! "$http_code" =~ ^2 ]]; then
        printf '  [HTTP %s] %s\n' "$http_code" \
            "$(printf '%s' "$body" | jq -r '.error.message // .message // .' 2>/dev/null || printf '%s' "$body")" >&2
    fi
    printf '%s' "$body" | jq -r '.token // empty'
}

npm_connect() {
    local token
    token=$(npm_token "$1" "$2")
    if [[ -z "$token" ]]; then
        echo "Fout: verbinding met NPM mislukt. Controleer e-mailadres en wachtwoord." >&2
        return 1
    fi
    printf '%s' "$token"
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
        \"block_exploits\": false,
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
    local token="$1" domain="$2"
    local response id
    response=$(npm_api POST "$token" "/nginx/certificates" "{
        \"provider\": \"letsencrypt\",
        \"domain_names\": [\"${domain}\"],
        \"meta\": {}
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
        \"block_exploits\": false,
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

npm_delete_proxy() {
    local result
    result=$(npm_api DELETE "$1" "/nginx/proxy-hosts/$2")
    ! printf '%s' "$result" | jq -e '.error' &>/dev/null
}

npm_delete_cert() {
    local result
    result=$(npm_api DELETE "$1" "/nginx/certificates/$2")
    ! printf '%s' "$result" | jq -e '.error' &>/dev/null
}
