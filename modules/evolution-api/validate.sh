#!/bin/bash
set -Eeuo pipefail
docker ps --format '{{.Names}}' | grep -q '^evolution-api_evolution-api' && echo "evolution-api: OK" || { echo "evolution-api: FAIL"; exit 1; }
