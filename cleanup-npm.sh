#!/usr/bin/env bash
# Verwijdert alle NPM proxy hosts en certificaten die in sites.csv staan.
set -euo pipefail

CSV="sites.csv"
NPM_URL="http://127.0.0.1:81/api"

# ── Controleer vereisten ──────────────────────────────────────────────────────

if ! command -v jq &>/dev/null; then
    echo "Fout: jq is vereist. Installeer met: apt install jq" >&2
    exit 1
fi

if [[ ! -f "$CSV" ]]; then
    echo "Fout: $CSV niet gevonden." >&2
    exit 1
fi

# ── NPM API-helper ────────────────────────────────────────────────────────────

npm_api() {
    local method="$1" token="$2" path="$3"
    local raw http_code response
    raw=$(curl -s -w "\n%{http_code}" -X "$method" "${NPM_URL}${path}" \
        -H "Authorization: Bearer ${token}")
    http_code=$(printf '%s' "$raw" | tail -1)
    response=$(printf '%s' "$raw" | head -n -1)
    if [[ ! "$http_code" =~ ^2 ]]; then
        printf '  [HTTP %s] %s\n' "$http_code" \
            "$(printf '%s' "$response" | jq -r '.error.message // .message // .' 2>/dev/null || printf '%s' "$response")" >&2
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

npm_find_proxy() {
    local token="$1" domain="$2"
    npm_api GET "$token" "/nginx/proxy-hosts" \
        | jq -r ".[] | select(.domain_names[] == \"${domain}\") | .id" 2>/dev/null | head -1 || true
}

npm_find_cert() {
    local token="$1" domain="$2"
    npm_api GET "$token" "/nginx/certificates" \
        | jq -r ".[] | select(.domain_names[] == \"${domain}\") | .id" 2>/dev/null | head -1 || true
}

# ── Invoer ────────────────────────────────────────────────────────────────────

echo "Sites uit ${CSV}:"
tail -n +2 "$CSV" | while IFS=',' read -r domain container network; do
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
TOKEN=$(npm_token "$NPM_EMAIL" "$NPM_PASSWORD")
if [[ -z "$TOKEN" ]]; then
    echo "MISLUKT"
    echo "Fout: controleer e-mailadres en wachtwoord." >&2
    exit 1
fi
echo "OK"

# ── Verwijder per site ────────────────────────────────────────────────────────

ERRORS=0

while IFS=',' read -r domain container network; do
    echo ""

    # Proxy host verwijderen
    printf "[%s] Proxy host... " "$domain"
    PROXY_ID=$(npm_find_proxy "$TOKEN" "$domain")
    if [[ -z "$PROXY_ID" ]]; then
        echo "niet gevonden"
    else
        RESULT=$(npm_api DELETE "$TOKEN" "/nginx/proxy-hosts/${PROXY_ID}")
        if printf '%s' "$RESULT" | jq -e '.error' &>/dev/null; then
            echo "MISLUKT"
            ERRORS=$((ERRORS + 1))
        else
            echo "verwijderd (id: ${PROXY_ID})"
        fi
    fi

    # Certificaat verwijderen
    printf "[%s] Certificaat... " "$domain"
    CERT_ID=$(npm_find_cert "$TOKEN" "$domain")
    if [[ -z "$CERT_ID" ]]; then
        echo "niet gevonden"
    else
        RESULT=$(npm_api DELETE "$TOKEN" "/nginx/certificates/${CERT_ID}")
        if printf '%s' "$RESULT" | jq -e '.error' &>/dev/null; then
            echo "MISLUKT"
            ERRORS=$((ERRORS + 1))
        else
            echo "verwijderd (id: ${CERT_ID})"
        fi
    fi

done < <(tail -n +2 "$CSV")

# ── Resultaat ─────────────────────────────────────────────────────────────────

echo ""
if [[ "$ERRORS" -eq 0 ]]; then
    echo "Klaar. Alles verwijderd."
else
    echo "Klaar met ${ERRORS} fout(en). Controleer de meldingen hierboven."
fi
