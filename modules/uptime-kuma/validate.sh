#!/bin/bash
set -Eeuo pipefail
docker ps --format '{{.Names}}' | grep -q '^uptime-kuma_uptime-kuma' && echo "uptime-kuma: OK" || { echo "uptime-kuma: FAIL"; exit 1; }
