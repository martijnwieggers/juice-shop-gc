#!/usr/bin/env bash
# Genereert docker-compose-gc.yml met een juice-shop-gc container per site.
# SSL en routing worden afgehandeld door de bestaande Nginx Proxy Manager.
set -euo pipefail

OUTPUT="docker-compose-gc.yml"

# ── Invoer ────────────────────────────────────────────────────────────────────

read -rp "Aantal sites: " NUM_SITES
if ! [[ "$NUM_SITES" =~ ^[1-9][0-9]*$ ]]; then
    echo "Fout: voer een geldig getal in." >&2
    exit 1
fi

read -rp "Eerste poort (standaard: 3001): " START_PORT
START_PORT="${START_PORT:-3001}"
if ! [[ "$START_PORT" =~ ^[0-9]+$ ]]; then
    echo "Fout: voer een geldige poort in." >&2
    exit 1
fi

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

    port=$START_PORT
    for initials in "${INITIALS_LIST[@]}"; do
        service="juice-shop-${initials}"
        salt=$(openssl rand -hex 20)
        salt_findit=$(openssl rand -hex 20)
        salt_fixit=$(openssl rand -hex 20)

        printf '  %s:\n'                              "$service"
        printf '    build:\n'
        printf '      context: .\n'
        printf '      dockerfile: Dockerfile\n'
        printf '    image: juice-shop-gc\n'
        printf '    restart: unless-stopped\n'
        printf '    ports:\n'
        printf '      - "%s:3000"\n'                  "$port"
        printf '    environment:\n'
        printf '      - NODE_ENV=graafschap-college\n'
        printf '      - CONTINUE_CODE_SALT=%s\n'      "$salt"
        printf '      - CONTINUE_CODE_SALT_FINDIT=%s\n' "$salt_findit"
        printf '      - CONTINUE_CODE_SALT_FIXIT=%s\n'  "$salt_fixit"
        printf '\n'

        ((port++))
    done

} > "$OUTPUT"

# ── Samenvatting + NPM-instellingen ───────────────────────────────────────────

echo ""
echo "Gegenereerd: $OUTPUT"
echo ""
printf "%-6s  %-30s  %-10s  %s\n" "Site" "Subdomein" "Poort" "NPM: Forward Hostname/IP → Port"
printf "%-6s  %-30s  %-10s  %s\n" "------" "------------------------------" "----------" "--------------------------------"

port=$START_PORT
for initials in "${INITIALS_LIST[@]}"; do
    subdomain="js-${initials}.wieggers.eu"
    printf "%-6s  %-30s  %-10s  localhost → %s\n" "$initials" "$subdomain" "$port" "$port"
    ((port++))
done

echo ""
echo "Stappen in Nginx Proxy Manager per site:"
echo "  1. Add Proxy Host"
echo "  2. Domain Names:          js-<initialen>.wieggers.eu"
echo "  3. Forward Hostname/IP:   localhost (of het server-IP)"
echo "  4. Forward Port:          zie tabel hierboven"
echo "  5. SSL tab → Request new certificate (Let's Encrypt)"
echo ""
echo "Containers starten:"
echo "  docker compose -f $OUTPUT up -d"
