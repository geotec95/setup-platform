#!/bin/bash
# modules/n8n/install.sh — instalador de referência. Todo novo módulo segue este padrão:
# 1) checa idempotência, 2) pede domínio, 3) gera env, 4) garante dependências (proxy),
# 5) deploy da stack, 6) valida.
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"
source "${SP_ROOT}/core/proxy.sh"
source "${SP_ROOT}/providers/aws/detect.sh"

SLUG="n8n"
UPDATE=false
[[ "${1:-}" == "--update" ]] && UPDATE=true

if sp::is_stack_up "$SLUG" && ! $UPDATE; then
  sp::warn "${SLUG} já está instalado. Use a ação 'Atualizar' para fazer pull da imagem mais recente."
  exit 0
fi

sp::docker::install
sp::proxy::ensure_traefik

# Reaproveita N8N_ENCRYPTION_KEY existente em updates — o n8n persiste a chave em
# /home/node/.n8n/config no primeiro boot; gerar uma nova a cada update quebra o
# container com "Mismatching encryption keys" (crash loop). Precisa rodar ANTES
# de perguntar o domínio (senão o DOMAIN recém-digitado seria sobrescrito pelo
# valor antigo salvo no .env — mesmo bug já corrigido em modules/observability).
ENV_FILE="${SP_ROOT}/modules/${SLUG}/.env"
if $UPDATE && [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
N8N_ENCRYPTION_KEY="${N8N_ENCRYPTION_KEY:-$(sp::gen_password 32)}"

DOMAIN="${DOMAIN:-$(sp::proxy::ask_domain "$SLUG")}"
DATA_DIR="$(sp::ensure_data_dir "$SLUG")"
chmod 700 "$DATA_DIR"
chown -R 1000:1000 "$DATA_DIR"  # imagem n8nio/n8n roda como usuário "node" (UID 1000)

{
  echo "DOMAIN=${DOMAIN}"
  echo "TZ=America/Sao_Paulo"
  echo "N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

sp::docker::ensure_network rede_publica
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
docker stack deploy -c "${SP_TEMPLATES_DIR}/compose/n8n.yml" "$SLUG"

sp::ok "n8n implantado. Aguarde ~30s para o certificado SSL e acesse: https://${DOMAIN}"
sp::log "INSTALL" "$SLUG" "domain=${DOMAIN} data_dir=${DATA_DIR}"
