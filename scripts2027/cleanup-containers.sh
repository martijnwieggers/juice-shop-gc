#!/usr/bin/env bash
# Stopt en verwijdert alle containers uit docker-compose-gc.yml.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT="${ROOT}/docker-compose-gc.yml"

if [[ ! -f "$OUTPUT" ]]; then
    echo "Fout: ${OUTPUT} niet gevonden. Draai eerst: bash scripts2027/add-site.sh" >&2
    exit 1
fi

echo "Containers die worden verwijderd:"
docker compose -f "$OUTPUT" ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null || true
echo ""

read -rp "Doorgaan? (j/N): " CONFIRM
if [[ "${CONFIRM,,}" != "j" ]]; then
    echo "Geannuleerd."
    exit 0
fi

docker compose -f "$OUTPUT" down
echo "Klaar."
