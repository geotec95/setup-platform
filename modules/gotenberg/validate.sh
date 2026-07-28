#!/bin/bash
# modules/gotenberg/validate.sh
set -Eeuo pipefail
docker ps --format '{{.Names}}' | grep -q '^gotenberg_gotenberg' && exit 0
exit 1
