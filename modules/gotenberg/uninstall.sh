#!/bin/bash
# modules/gotenberg/uninstall.sh
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"

SLUG="gotenberg"

sp::confirm "Remover a stack '${SLUG}'?" || { sp::warn "Cancelado."; exit 0; }
docker stack rm "$SLUG"
sp::ok "Stack '${SLUG}' removida (serviço sem dados persistentes -- nada pra limpar em /data)."
sp::log "UNINSTALL" "$SLUG" "-"
