#!/bin/bash
# modules/client-dashboard/uninstall.sh — remove o módulo client-dashboard por
# completo. Como cada cliente é uma stack/Organization independente, este
# script primeiro remove CADA cliente provisionado (via remove-client.sh) e só
# então limpa a base do módulo.
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"

MODULE_DIR="${SP_MODULES_DIR}/client-dashboard"
CLIENTS_DIR="${MODULE_DIR}/clients"

if [[ -d "$CLIENTS_DIR" ]]; then
  shopt -s nullglob
  for client_env in "${CLIENTS_DIR}"/*/.env; do
    slug="$(basename "$(dirname "$client_env")")"
    sp::info "Cliente detectado: ${slug}"
    sp::confirm "Remover o dashboard do cliente '${slug}' agora?" && \
      bash "${MODULE_DIR}/remove-client.sh" "$slug"
  done
  shopt -u nullglob
else
  sp::info "Nenhum cliente provisionado encontrado."
fi

sp::confirm "Remover a base do módulo client-dashboard (modules/client-dashboard/.env)?" && {
  rm -f "${MODULE_DIR}/.env"
  sp::ok "Base do módulo removida. Os clientes ainda existentes precisam ser removidos individualmente com remove-client.sh."
}

sp::log "UNINSTALL" "client-dashboard" "uninstall executado"
