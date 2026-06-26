#!/usr/bin/env bash
# Genereert docker-compose-gc.yml met Traefik + een juice-shop-gc container per site.
set -euo pipefail

OUTPUT="docker-compose-gc.yml"

# ── Invoer ────────────────────────────────────────────────────────────────────

read -rp "E-mailadres voor Let's Encrypt: " LE_EMAIL

read -rp "Aantal sites: " NUM_SITES
if ! [[ "$NUM_SITES" =~ ^[1-9][0-9]*$ ]]; then
    echo "Fout: voer een geldig getal in." >&2
    exit 1
fi

declare -a INITIALS_LIST
for ((i = 1; i <= NUM_SITES; i++)); do
    read -rp "Initialen site $i: " initials
    if [[ -z "$initials" ]]; then
        echo "Fout: initialen mogen niet leeg zijn." >&2
        exit 1
    fi
    INITIALS_LIST+=("${initials,,}")  # opslaan als lowercase
done

# ── Genereer docker-compose-gc.yml ────────────────────────────────────────────

{
    printf 'services:\n'

    # Traefik
    printf '  traefik:\n'
    printf '    image: traefik:v3.3\n'
    printf '    restart: unless-stopped\n'
    printf '    ports:\n'
    printf '      - "80:80"\n'
    printf '      - "443:443"\n'
    printf '    volumes:\n'
    printf '      - /var/run/docker.sock:/var/run/docker.sock:ro\n'
    printf '      - ./letsencrypt/acme.json:/letsencrypt/acme.json\n'
    printf '    command:\n'
    printf '      - --providers.docker=true\n'
    printf '      - --providers.docker.exposedbydefault=false\n'
    printf '      - --entrypoints.web.address=:80\n'
    printf '      - --entrypoints.web.http.redirections.entrypoint.to=websecure\n'
    printf '      - --entrypoints.web.http.redirections.entrypoint.scheme=https\n'
    printf '      - --entrypoints.websecure.address=:443\n'
    printf '      - --certificatesresolvers.letsencrypt.acme.httpchallenge=true\n'
    printf '      - --certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web\n'
    printf '      - --certificatesresolvers.letsencrypt.acme.email=%s\n' "$LE_EMAIL"
    printf '      - --certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json\n'
    printf '    networks:\n'
    printf '      - proxy\n'
    printf '\n'

    # Juice-shop containers
    for initials in "${INITIALS_LIST[@]}"; do
        service="juice-shop-${initials}"
        subdomain="js-${initials}.wieggers.eu"
        salt=$(openssl rand -hex 20)
        salt_findit=$(openssl rand -hex 20)
        salt_fixit=$(openssl rand -hex 20)

        printf '  %s:\n'                                                        "$service"
        printf '    image: juice-shop-gc\n'
        printf '    restart: unless-stopped\n'
        printf '    environment:\n'
        printf '      - NODE_ENV=graafschap-college\n'
        printf '      - CONTINUE_CODE_SALT=%s\n'                               "$salt"
        printf '      - CONTINUE_CODE_SALT_FINDIT=%s\n'                        "$salt_findit"
        printf '      - CONTINUE_CODE_SALT_FIXIT=%s\n'                         "$salt_fixit"
        printf '    labels:\n'
        printf '      - "traefik.enable=true"\n'
        printf '      - "traefik.http.routers.%s.rule=Host(`%s`)"\n'           "$service" "$subdomain"
        printf '      - "traefik.http.routers.%s.entrypoints=websecure"\n'     "$service"
        printf '      - "traefik.http.routers.%s.tls.certresolver=letsencrypt"\n' "$service"
        printf '      - "traefik.http.services.%s.loadbalancer.server.port=3000"\n' "$service"
        printf '    networks:\n'
        printf '      - proxy\n'
        printf '\n'
    done

    # Netwerk
    printf 'networks:\n'
    printf '  proxy:\n'

} > "$OUTPUT"

# ── Maak acme.json aan met juiste rechten ─────────────────────────────────────

mkdir -p letsencrypt
touch letsencrypt/acme.json
chmod 600 letsencrypt/acme.json

# ── Samenvatting ──────────────────────────────────────────────────────────────

echo ""
echo "Gegenereerd: $OUTPUT"
echo ""
echo "Sites:"
for initials in "${INITIALS_LIST[@]}"; do
    printf "  https://js-%s.wieggers.eu\n" "$initials"
done
echo ""
echo "Volgende stap:"
echo "  docker compose -f $OUTPUT up -d"
