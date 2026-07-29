#!/bin/bash
# modules/central-admin/uninstall.sh
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"

SLUG="central-admin"

sp::confirm "Remover a stack '${SLUG}'?" || { sp::warn "Cancelado."; exit 0; }
docker stack rm "$SLUG"
sp::ok "Stack '${SLUG}' removida. Dados em /data/${SLUG} preservados (remova manualmente se quiser)."
sp::log "UNINSTALL" "$SLUG" "-"
