#!/bin/bash
set -Eeuo pipefail
docker ps --format '{{.Names}}' | grep -q '^n8n_n8n' && echo "n8n: OK" || { echo "n8n: FAIL"; exit 1; }
