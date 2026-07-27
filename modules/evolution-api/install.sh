#!/bin/bash
# modules/evolution-api/install.sh — segue o padrão de modules/n8n/install.sh.
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"
source "${SP_ROOT}/core/proxy.sh"
source "${SP_ROOT}/providers/aws/detect.sh"

SLUG="evolution-api"
UPDATE=false
[[ "${1:-}" == "--update" ]] && UPDATE=true

if sp::is_stack_up "$SLUG" && ! $UPDATE; then
  sp::warn "${SLUG} já está instalado. Use a ação 'Atualizar' para fazer pull da imagem mais recente."
  exit 0
fi

# Reaproveita credenciais existentes em updates — precisa rodar ANTES de
# perguntar o domínio (mesmo motivo do bug já corrigido em observability/n8n).
ENV_FILE="${SP_ROOT}/modules/${SLUG}/.env"
if $UPDATE && [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(sp::gen_password 24)}"
API_KEY="${API_KEY:-$(sp::gen_password 32)}"

sp::docker::install
sp::proxy::ensure_traefik

DOMAIN="${DOMAIN:-$(sp::proxy::ask_domain "$SLUG")}"

DATA_DIR="$(sp::ensure_data_dir "$SLUG")"
mkdir -p "${DATA_DIR}/postgres" "${DATA_DIR}/redis" "${DATA_DIR}/instances"
chown -R 999:999 "${DATA_DIR}/postgres"   # postgres:16-alpine roda como uid "postgres"
chown -R 999:999 "${DATA_DIR}/redis"      # redis:7-alpine roda como uid "redis" (mesmo 999 por coincidência)

{
  echo "DOMAIN=${DOMAIN}"
  echo "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}"
  echo "API_KEY=${API_KEY}"
  echo "TZ=America/Sao_Paulo"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

sp::docker::ensure_network rede_publica
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
docker stack deploy -c "${SP_TEMPLATES_DIR}/compose/evolution-api.yml" "$SLUG"

sp::ok "Evolution API implantada. Aguarde ~30s para o certificado SSL e acesse: https://${DOMAIN}"
sp::ok "API_KEY (header 'apikey' em toda chamada) -> ${API_KEY}"
sp::warn "Guarde a API_KEY acima em local seguro (também salva em ${ENV_FILE}, com permissão 600)."
sp::info "Próximo passo (manual, exige seu celular): criar uma instância e escanear o QR code."
sp::info "  curl -X POST https://${DOMAIN}/instance/create -H 'apikey: ${API_KEY}' -H 'Content-Type: application/json' -d '{\"instanceName\":\"principal\",\"qrcode\":true,\"integration\":\"WHATSAPP-BAILEYS\"}'"
sp::info "  curl https://${DOMAIN}/instance/connect/principal -H 'apikey: ${API_KEY}'   # retorna o QR code em base64"
sp::log "INSTALL" "$SLUG" "domain=${DOMAIN}"
