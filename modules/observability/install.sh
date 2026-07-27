#!/bin/bash
# modules/observability/install.sh — instala o stack de observabilidade das
# aplicações (Prometheus + Grafana + Loki + Promtail + cAdvisor +
# node-exporter). Segue o mesmo padrão do modules/n8n/install.sh:
# 1) checa idempotência, 2) pede domínio (só do Grafana, único serviço
# público), 3) gera credenciais/env, 4) garante dependências (Docker/proxy),
# 5) materializa configs em /data, 6) deploy da stack via Swarm.
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"
source "${SP_ROOT}/core/proxy.sh"
source "${SP_ROOT}/providers/aws/detect.sh"

SLUG="observability"
UPDATE=false
[[ "${1:-}" == "--update" ]] && UPDATE=true

if sp::is_stack_up "$SLUG" && ! $UPDATE; then
  sp::warn "${SLUG} já está instalado. Use a ação 'Atualizar' para fazer pull das imagens mais recentes."
  exit 0
fi

sp::docker::install
sp::proxy::ensure_traefik

# Reaproveita GRAFANA_ADMIN_PASSWORD/INGEST_PASSWORD existentes em updates,
# evitando invalidar sessões/credenciais já em uso a cada `--update`. Precisa
# rodar ANTES de perguntar o domínio: se sourcear depois, o DOMAIN/INGEST_DOMAIN
# recém-digitados seriam sobrescritos pelos valores antigos salvos no .env.
ENV_FILE="${SP_ROOT}/modules/${SLUG}/.env"
if $UPDATE && [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

# Só o Grafana tem painel web público — é o único que precisa de domínio/HTTPS.
DOMAIN="$(sp::proxy::ask_domain "grafana")"
# Domínio separado para os endpoints de ingestão (remote_write do Prometheus
# e push do Loki) usados por agentes remotos (modules/remote-agent) rodando
# em EC2 de clientes, inclusive em outras contas AWS.
INGEST_DOMAIN="$(sp::proxy::ask_domain "ingest")"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-$(sp::gen_password 24)}"
INGEST_USER="${INGEST_USER:-ingest}"
INGEST_PASSWORD="${INGEST_PASSWORD:-$(sp::gen_password 24)}"
# Hash apr1 (formato aceito pelo middleware basicauth do Traefik). Recalculado
# sempre a partir de INGEST_PASSWORD — não precisa ser "lembrado" entre updates.
INGEST_HTPASSWD_ENTRY="${INGEST_USER}:$(openssl passwd -apr1 "$INGEST_PASSWORD")"

# --- Diretórios de dados (persistência sempre em /data/<tool>, nunca em volume anônimo) ---
# Cada imagem roda como um usuário não-root diferente; sem o chown correto o
# container crasha ao tentar escrever no volume (mesmo bug encontrado no n8n).
sp::ensure_data_dir "${SLUG}/prometheus" >/dev/null
chown -R 65534:65534 "${SP_DATA_ROOT}/${SLUG}/prometheus"  # prom/prometheus roda como "nobody"
sp::ensure_data_dir "${SLUG}/grafana" >/dev/null
chown -R 472:472 "${SP_DATA_ROOT}/${SLUG}/grafana"         # grafana/grafana roda como uid "grafana"
sp::ensure_data_dir "${SLUG}/loki" >/dev/null
chown -R 10001:10001 "${SP_DATA_ROOT}/${SLUG}/loki"        # grafana/loki roda como uid "loki"
sp::ensure_data_dir "${SLUG}/tempo" >/dev/null
chown -R 10001:10001 "${SP_DATA_ROOT}/${SLUG}/tempo"       # grafana/tempo também roda como uid 10001

# --- Diretórios de configuração (materializados a partir dos templates a cada install/update) ---
CONF_DIR="${SP_DATA_ROOT}/${SLUG}/config"
mkdir -p \
  "${CONF_DIR}/prometheus" \
  "${CONF_DIR}/loki" \
  "${CONF_DIR}/tempo" \
  "${CONF_DIR}/promtail" \
  "${CONF_DIR}/grafana/provisioning/datasources" \
  "${CONF_DIR}/grafana/provisioning/dashboards/json"
# Montados :ro por processos rodando com UIDs diferentes (65534/472/10001) —
# precisa ser legível por "outros", não só pelo grupo dono (root).
chmod -R a+rX "$CONF_DIR"

cp -f "${SP_TEMPLATES_DIR}/observability/prometheus.yml.tpl"              "${CONF_DIR}/prometheus/prometheus.yml"
cp -f "${SP_TEMPLATES_DIR}/observability/loki-config.yml"                 "${CONF_DIR}/loki/loki-config.yml"
cp -f "${SP_TEMPLATES_DIR}/observability/tempo-config.yml"                "${CONF_DIR}/tempo/tempo-config.yml"
cp -f "${SP_TEMPLATES_DIR}/observability/promtail-config.yml"             "${CONF_DIR}/promtail/promtail-config.yml"
cp -f "${SP_TEMPLATES_DIR}/observability/grafana-datasources.yml"         "${CONF_DIR}/grafana/provisioning/datasources/datasources.yml"
cp -f "${SP_TEMPLATES_DIR}/observability/grafana-dashboards-provisioning.yml" "${CONF_DIR}/grafana/provisioning/dashboards/dashboards.yml"
cp -f "${SP_TEMPLATES_DIR}/observability/dashboards/docker-overview.json" "${CONF_DIR}/grafana/provisioning/dashboards/json/docker-overview.json"
cp -f "${SP_TEMPLATES_DIR}/observability/dashboards/remote-clients.json" "${CONF_DIR}/grafana/provisioning/dashboards/json/remote-clients.json"

# --- .env do módulo ---
# INGEST_HTPASSWD_ENTRY contém "$" (hash apr1) — usar printf %q pra escapar
# corretamente, senão o próximo `source "$ENV_FILE"` (ex: num --update) tenta
# expandir "$apr1"/"$xyz..." como variáveis inexistentes e corrompe o hash.
{
  echo "DOMAIN=${DOMAIN}"
  echo "INGEST_DOMAIN=${INGEST_DOMAIN}"
  echo "GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}"
  echo "INGEST_USER=${INGEST_USER}"
  echo "INGEST_PASSWORD=${INGEST_PASSWORD}"
  printf 'INGEST_HTPASSWD_ENTRY=%q\n' "$INGEST_HTPASSWD_ENTRY"
  echo "TZ=America/Sao_Paulo"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

sp::docker::ensure_network rede_publica
# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
docker stack deploy -c "${SP_TEMPLATES_DIR}/compose/observability.yml" "$SLUG"

sp::ok "Observabilidade implantada. Aguarde ~30s para o certificado SSL e acesse: https://${DOMAIN}"
sp::ok "Login do Grafana -> usuário: admin / senha: ${GRAFANA_ADMIN_PASSWORD}"
sp::ok "Endpoint de ingestão (agentes remotos) -> https://${INGEST_DOMAIN} / usuário: ${INGEST_USER} / senha: ${INGEST_PASSWORD}"
sp::warn "Guarde as credenciais acima em local seguro (também salvas em ${ENV_FILE}, com permissão 600)."
sp::log "INSTALL" "$SLUG" "domain=${DOMAIN} ingest_domain=${INGEST_DOMAIN}"
