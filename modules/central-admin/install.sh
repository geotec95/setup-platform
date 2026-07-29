#!/bin/bash
# modules/central-admin/install.sh — instala a área administrativa (formulário
# de provisionamento de novo cliente). Segue o mesmo padrão de módulo nginx
# estático do client-dashboard, mas é único (não duplicado por cliente).
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"
source "${SP_ROOT}/core/proxy.sh"
source "${SP_ROOT}/providers/aws/detect.sh"

SLUG="central-admin"
UPDATE=false
[[ "${1:-}" == "--update" ]] && UPDATE=true

if sp::is_stack_up "$SLUG" && ! $UPDATE; then
  sp::warn "${SLUG} já está instalado. Use a ação 'Atualizar' para recarregar o formulário."
  exit 0
fi

sp::docker::install
sp::proxy::ensure_traefik

ENV_FILE="${SP_ROOT}/modules/${SLUG}/.env"
if $UPDATE && [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

DOMAIN="${DOMAIN:-$(sp::proxy::ask_domain "central")}"
# Webhook fixo do motor de provisionamento -- opcional, ENTER pra usar o
# padrão (mesmo domínio de n8n já usado pelo resto da plataforma).
if [[ -z "${PROVISION_WEBHOOK_URL:-}" ]]; then
  read -r -p "$(echo -e "${C_WHITE}URL do webhook de provisionamento (ENTER pra usar https://n8n.arcuscloud.com.br/webhook/provision-client): ${C_RESET}")" PROVISION_WEBHOOK_URL
fi
PROVISION_WEBHOOK_URL="${PROVISION_WEBHOOK_URL:-https://n8n.arcuscloud.com.br/webhook/provision-client}"

DATA_DIR="$(sp::ensure_data_dir "${SLUG}/html")"

REMAP_LOGO_DATA_URI="data:image/png;base64,$(base64 -w0 "${SP_ROOT}/logos/vertical-colorida-principal.png")"

sed \
  -e "s|{{PROVISION_WEBHOOK_URL}}|${PROVISION_WEBHOOK_URL}|g" \
  "${SP_TEMPLATES_DIR}/central-admin/index.html" \
  | awk -v uri="$REMAP_LOGO_DATA_URI" '{gsub(/{{REMAP_LOGO_DATA_URI}}/, uri); print}' \
  > "${DATA_DIR}/index.html"

{
  echo "DOMAIN=${DOMAIN}"
  echo "PROVISION_WEBHOOK_URL=${PROVISION_WEBHOOK_URL}"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

sp::docker::ensure_network rede_publica
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
docker stack deploy -c "${SP_TEMPLATES_DIR}/compose/central-admin.yml" "$SLUG"
sp::docker::force_restart "${SLUG}_web"

sp::ok "Área administrativa implantada. Aguarde ~30s para o certificado SSL e acesse: https://${DOMAIN}"
sp::warn "Não esqueça de proteger esse domínio com Cloudflare Access (nunca deixar exposto sem login)."
sp::log "INSTALL" "$SLUG" "domain=${DOMAIN}"
