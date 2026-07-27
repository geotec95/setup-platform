#!/bin/bash
# modules/uptime-kuma/install.sh — segue o mesmo padrão de modules/n8n/install.sh:
# 1) checa idempotência, 2) pede domínio, 3) gera env, 4) garante dependências
# (proxy), 5) deploy da stack, 6) valida.
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"
source "${SP_ROOT}/core/proxy.sh"
source "${SP_ROOT}/providers/aws/detect.sh"

SLUG="uptime-kuma"
UPDATE=false
[[ "${1:-}" == "--update" ]] && UPDATE=true

if sp::is_stack_up "$SLUG" && ! $UPDATE; then
  sp::warn "${SLUG} já está instalado. Use a ação 'Atualizar' para fazer pull da imagem mais recente."
  exit 0
fi

sp::docker::install
sp::proxy::ensure_traefik

DOMAIN="$(sp::proxy::ask_domain "$SLUG")"
DATA_DIR="$(sp::ensure_data_dir "$SLUG")"
# Imagem louislam/uptime-kuma (tag release, não-rootless) roda como root
# dentro do container — sem chown necessário, ao contrário do n8n/observability.

ENV_FILE="${SP_ROOT}/modules/${SLUG}/.env"
{
  echo "DOMAIN=${DOMAIN}"
  echo "TZ=America/Sao_Paulo"
} > "$ENV_FILE"

sp::docker::ensure_network rede_publica
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
docker stack deploy -c "${SP_TEMPLATES_DIR}/compose/uptime-kuma.yml" --detach=true "$SLUG"

sp::ok "Uptime Kuma implantado. Aguarde ~30s para o certificado SSL e acesse: https://${DOMAIN}"
sp::ok "Crie a conta de administrador no primeiro acesso (tela de setup do próprio Uptime Kuma)."
sp::log "INSTALL" "$SLUG" "domain=${DOMAIN} data_dir=${DATA_DIR}"
