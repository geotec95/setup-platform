#!/bin/bash
# modules/client-dashboard/install.sh — instala a BASE do módulo client-dashboard.
#
# Este módulo não sobe nenhuma stack "genérica": ele só garante os pré-requisitos
# (Docker, Traefik e, principalmente, o módulo `observability` com o Grafana
# compartilhado já rodando). O provisionamento de fato — um dashboard branded
# por cliente — é feito depois, individualmente, com:
#
#   bash modules/client-dashboard/new-client.sh <slug> <dominio> <cor-hex> <url-logo>
#
# Ver o comentário no topo de new-client.sh para a decisão de arquitetura
# completa (por que não usamos um Grafana por cliente).
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"
source "${SP_ROOT}/core/proxy.sh"

SLUG="client-dashboard"

sp::docker::install
sp::proxy::ensure_traefik

if ! sp::is_stack_up observability; then
  sp::err "Módulo 'observability' não está instalado/rodando."
  sp::err "O client-dashboard depende do Grafana compartilhado provisionado por esse módulo."
  sp::err "Instale 'observability' primeiro e rode este install.sh novamente."
  exit 1
fi
sp::ok "Módulo 'observability' detectado — Grafana compartilhado disponível."

OBS_ENV="${SP_MODULES_DIR}/observability/.env"
if [[ ! -f "$OBS_ENV" ]]; then
  sp::err "Arquivo ${OBS_ENV} não encontrado. A instalação do observability parece incompleta."
  exit 1
fi

sp::ensure_data_dir "client-dashboard" >/dev/null
mkdir -p "${SP_MODULES_DIR}/${SLUG}/clients"

# .env "base" do módulo — referencia o Grafana compartilhado, sem duplicar
# segredos (a senha real do admin do Grafana vive só em modules/observability/.env).
ENV_FILE="${SP_MODULES_DIR}/${SLUG}/.env"
if [[ ! -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a; source "$OBS_ENV"; set +a
  {
    echo "GRAFANA_BASE_URL=${GRAFANA_BASE_URL:-}"
    echo "GRAFANA_ADMIN_USER=${GRAFANA_ADMIN_USER:-admin}"
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
fi

sp::ok "Base do módulo client-dashboard pronta."
sp::info "Para provisionar o dashboard de um novo cliente, rode:"
sp::info "  bash ${SP_MODULES_DIR}/${SLUG}/new-client.sh <slug-cliente> <dominio-cliente> <cor-hex> <url-logo> [nome-cliente]"
sp::log "INSTALL" "$SLUG" "base pronta, aguardando provisionamento por cliente via new-client.sh"
