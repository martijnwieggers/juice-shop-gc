#!/usr/bin/env bash
# Stopt en verwijdert alle containers uit docker-compose-gc.yml.
set -euo pipefail

COMPOSE_FILE="docker-compose-gc.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "Fout: $COMPOSE_FILE niet gevonden. Draai eerst: bash generate-compose.sh" >&2
    exit 1
fi

echo "Containers die worden verwijderd:"
docker compose -f "$COMPOSE_FILE" ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null || true
echo ""

read -rp "Doorgaan? (j/N): " CONFIRM
if [[ "${CONFIRM,,}" != "j" ]]; then
    echo "Geannuleerd."
    exit 0
fi

docker compose -f "$COMPOSE_FILE" down
echo "Klaar."
