#!/usr/bin/env bash
# Stap 1: Genereert docker-compose-gc.yml en sites.csv.
# Daarna: docker compose -f docker-compose-gc.yml up -d
# DNS-records instellen en dan: bash configure-npm.sh
set -euo pipefail

OUTPUT="docker-compose-gc.yml"
CSV="sites.csv"

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

# ── Genereer sites.csv ────────────────────────────────────────────────────────

{
    printf 'domain,container,network\n'
    for initials in "${INITIALS_LIST[@]}"; do
        printf 'js-%s.wieggers.eu,juice-shop-%s,%s\n' "$initials" "$initials" "$NPM_NETWORK"
    done
} > "$CSV"

# ── Samenvatting ──────────────────────────────────────────────────────────────

echo ""
echo "Gegenereerd: $OUTPUT"
echo "Gegenereerd: $CSV"
echo ""
printf "%-10s  %-32s  %s\n" "Site" "Subdomein" "Container"
printf "%-10s  %-32s  %s\n" "----------" "--------------------------------" "----------------------------"
for initials in "${INITIALS_LIST[@]}"; do
    printf "%-10s  %-32s  %s\n" "$initials" "js-${initials}.wieggers.eu" "juice-shop-${initials}"
done
echo ""
echo "Volgende stappen:"
echo "  1. Stel DNS-records in voor bovenstaande subdomeinen"
echo "  2. docker compose -f $OUTPUT up -d"
echo "  3. bash configure-npm.sh"
