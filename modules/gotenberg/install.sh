#!/bin/bash
# modules/gotenberg/install.sh — instala o conversor HTML->PDF usado pelo
# n8n pra gerar os relatórios mensais de cliente (ver
# templates/n8n-workflows/monthly-client-report.json). Serviço headless,
# sem domínio/HTTPS -- só precisa estar na mesma rede Docker que o n8n.
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"

SLUG="gotenberg"
UPDATE=false
[[ "${1:-}" == "--update" ]] && UPDATE=true

if sp::is_stack_up "$SLUG" && ! $UPDATE; then
  sp::warn "${SLUG} já está instalado. Use a ação 'Atualizar' para fazer pull da imagem mais recente."
  exit 0
fi

sp::docker::install
sp::docker::ensure_network rede_publica
docker stack deploy -c "${SP_TEMPLATES_DIR}/compose/gotenberg.yml" "$SLUG"

sp::ok "Gotenberg implantado. Acessível internamente em http://gotenberg:3000 (sem exposição pública)."
sp::log "INSTALL" "$SLUG" "internal-only"
