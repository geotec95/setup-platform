#!/bin/bash
# modules/central-admin/validate.sh
set -Eeuo pipefail
docker ps --format '{{.Names}}' | grep -q '^central-admin_' && exit 0
exit 1
