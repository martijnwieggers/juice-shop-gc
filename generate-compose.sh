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

    # Netwerk als extern declareren (NPM beheert het)
    printf 'networks:\n'
    printf '  %s:\n'        "$NPM_NETWORK"
    printf '    external: true\n'

} > "$OUTPUT"

# ── Samenvatting + NPM-instellingen ───────────────────────────────────────────

echo ""
echo "Gegenereerd: $OUTPUT"
echo ""
printf "%-10s  %-30s  %-30s  %s\n" "Site" "Subdomein" "NPM Hostname" "NPM Port"
printf "%-10s  %-30s  %-30s  %s\n" "----------" "------------------------------" "------------------------------" "---------"

for initials in "${INITIALS_LIST[@]}"; do
    subdomain="js-${initials}.wieggers.eu"
    container="juice-shop-${initials}"
    printf "%-10s  %-30s  %-30s  %s\n" "$initials" "$subdomain" "$container" "3000"
done

echo ""
echo "Stappen in Nginx Proxy Manager per site:"
echo "  1. Add Proxy Host"
echo "  2. Domain Names:          js-<initialen>.wieggers.eu"
echo "  3. Forward Hostname/IP:   <containernaam uit tabel hierboven>"
echo "  4. Forward Port:          3000"
echo "  5. SSL tab → Request new certificate (Let's Encrypt)"
echo ""
echo "Containers starten:"
echo "  docker compose -f $OUTPUT up -d"
