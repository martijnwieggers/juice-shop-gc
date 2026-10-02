#!/usr/bin/env bash
# Genereert docker-compose-gc.yml vanuit sites.csv.
# sites.csv-formaat: domain,container,network,salt,salt_findit,salt_fixit
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
CSV="${ROOT}/sites.csv"
OUTPUT="${ROOT}/docker-compose-gc.yml"

if [[ ! -f "$CSV" ]]; then
    echo "Fout: ${CSV} niet gevonden." >&2
    echo "Voeg eerst een site toe met: bash scripts2027/add-site.sh" >&2
    exit 1
fi

COUNT=$(tail -n +2 "$CSV" | grep -c '.' || true)
if [[ "$COUNT" -eq 0 ]]; then
    echo "Fout: ${CSV} bevat geen sites." >&2
    exit 1
fi

# Verzamel unieke netwerken voor de networks-sectie
mapfile -t NETWORKS < <(tail -n +2 "$CSV" | cut -d',' -f3 | sort -u)

{
    printf 'services:\n'

    while IFS=',' read -r domain container network salt salt_findit salt_fixit; do
        printf '  %s:\n'                                 "$container"
        printf '    build:\n'
        printf '      context: .\n'
        printf '      dockerfile: Dockerfile\n'
        printf '    image: juice-shop-gc\n'
        printf '    container_name: %s\n'                "$container"
        printf '    restart: unless-stopped\n'
        printf '    environment:\n'
        printf '      - NODE_ENV=graafschap-college\n'
        printf '      - CONTINUE_CODE_SALT=%s\n'         "$salt"
        printf '      - CONTINUE_CODE_SALT_FINDIT=%s\n'  "$salt_findit"
        printf '      - CONTINUE_CODE_SALT_FIXIT=%s\n'   "$salt_fixit"
        printf '    networks:\n'
        printf '      - %s\n'                            "$network"
        printf '\n'
    done < <(tail -n +2 "$CSV")

    printf 'networks:\n'
    for net in "${NETWORKS[@]}"; do
        printf '  %s:\n'     "$net"
        printf '    external: true\n'
    done

} > "$OUTPUT"

echo "Gegenereerd: ${OUTPUT} (${COUNT} service(s))"
