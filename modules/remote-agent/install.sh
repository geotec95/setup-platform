#!/bin/bash
# modules/remote-agent/install.sh — instala o agente leve de observabilidade
# (Prometheus em modo agent + node-exporter + cAdvisor + Promtail) numa EC2 de
# CLIENTE, empurrando métricas/logs pro módulo observability central via
# HTTPS + Basic Auth. Não expõe painel próprio, não precisa de Traefik/domínio
# aqui — por isso não segue 100% o padrão de modules/n8n/install.sh nesse ponto.
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"
source "${SP_ROOT}/providers/aws/detect.sh"

SLUG="remote-agent"
UPDATE=false
[[ "${1:-}" == "--update" ]] && UPDATE=true

if sp::is_stack_up "$SLUG" && ! $UPDATE; then
  sp::warn "${SLUG} já está instalado. Use a ação 'Atualizar' para fazer pull das imagens mais recentes."
  exit 0
fi

sp::docker::install
sp::docker::init_swarm "$(sp::aws::private_ip 2>/dev/null || true)"

ENV_FILE="${SP_ROOT}/modules/${SLUG}/.env"
if $UPDATE && [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

CENTRAL_INGEST_DOMAIN="${CENTRAL_INGEST_DOMAIN:-$(sp::ask "Domínio de ingestão do observability central (ex: ingest.arcuscloud.com.br)")}"
INGEST_USER="${INGEST_USER:-$(sp::ask "Usuário de ingestão (mostrado ao instalar o observability central)")}"
INGEST_PASSWORD="${INGEST_PASSWORD:-$(sp::ask "Senha de ingestão (mostrada ao instalar o observability central)")}"
CLIENT_LABEL="${CLIENT_LABEL:-$(sp::ask "Identificador deste cliente/servidor (ex: geotec-prod, sem espaços)")}"

# Scrape de métricas de aplicação (RED: rate/errors/duration) — opcional, ao
# contrário dos campos acima (por isso não usa sp::ask, que exige resposta).
# Requer que o container da app exponha /metrics (ex: django-prometheus,
# prometheus-fastapi-instrumentator, prometheus-flask-exporter) e esteja
# alcançável pelo nome na mesma rede Docker do remote-agent (rede_publica) —
# ver "docker network connect rede_publica <container-da-app>".
if [[ -z "${APP_CONTAINER:-}" ]]; then
  read -r -p "$(echo -e "${C_WHITE}Nome do container da app pra monitorar métricas (ENTER pra pular): ${C_RESET}")" APP_CONTAINER
fi
if [[ -n "${APP_CONTAINER:-}" && -z "${APP_METRICS_PORT:-}" ]]; then
  read -r -p "$(echo -e "${C_WHITE}Porta do endpoint /metrics dessa app (ex: 8000): ${C_RESET}")" APP_METRICS_PORT
fi

if [[ -n "${APP_CONTAINER:-}" && -n "${APP_METRICS_PORT:-}" ]]; then
  APP_SCRAPE_CONFIG="  - job_name: app
    metrics_path: /metrics
    static_configs:
      - targets: [\"${APP_CONTAINER}:${APP_METRICS_PORT}\"]"
else
  APP_SCRAPE_CONFIG="# nenhuma app configurada para scrape de métricas — rode com --update pra adicionar"
fi

DATA_DIR="$(sp::ensure_data_dir "$SLUG")"
chown -R 65534:65534 "${DATA_DIR}"  # prom/prometheus (agent mode) roda como "nobody"

CONF_DIR="${SP_DATA_ROOT}/${SLUG}/config"
mkdir -p "${CONF_DIR}" "${SP_DATA_ROOT}/${SLUG}/prometheus-agent"
chown -R 65534:65534 "${SP_DATA_ROOT}/${SLUG}/prometheus-agent"
chmod 700 "$CONF_DIR"

sed -e "s|{{CENTRAL_INGEST_DOMAIN}}|${CENTRAL_INGEST_DOMAIN}|g" \
    -e "s|{{INGEST_USER}}|${INGEST_USER}|g" \
    -e "s|{{INGEST_PASSWORD}}|${INGEST_PASSWORD}|g" \
    -e "s|{{CLIENT_LABEL}}|${CLIENT_LABEL}|g" \
    "${SP_TEMPLATES_DIR}/remote-agent/prometheus-agent.yml.tpl" \
  | awk -v cfg="$APP_SCRAPE_CONFIG" '{gsub(/{{APP_SCRAPE_CONFIG}}/, cfg); print}' \
  > "${CONF_DIR}/prometheus-agent.yml"

sed -e "s|{{CENTRAL_INGEST_DOMAIN}}|${CENTRAL_INGEST_DOMAIN}|g" \
    -e "s|{{INGEST_USER}}|${INGEST_USER}|g" \
    -e "s|{{INGEST_PASSWORD}}|${INGEST_PASSWORD}|g" \
    -e "s|{{CLIENT_LABEL}}|${CLIENT_LABEL}|g" \
    "${SP_TEMPLATES_DIR}/remote-agent/promtail-config.yml.tpl" > "${CONF_DIR}/promtail-config.yml"

# Ambos os arquivos contêm INGEST_PASSWORD em texto claro — nunca world-readable
# (achado C3 da auditoria de segurança: estavam 644, legíveis por qualquer
# usuário local da EC2 do cliente).
chown 65534:65534 "${CONF_DIR}/prometheus-agent.yml"  # lido pelo prometheus-agent, roda como "nobody"
chmod 640 "${CONF_DIR}/prometheus-agent.yml"
chown root:root "${CONF_DIR}/promtail-config.yml"      # lido pelo promtail, roda como root
chmod 600 "${CONF_DIR}/promtail-config.yml"

{
  echo "CENTRAL_INGEST_DOMAIN=${CENTRAL_INGEST_DOMAIN}"
  echo "INGEST_USER=${INGEST_USER}"
  echo "INGEST_PASSWORD=${INGEST_PASSWORD}"
  echo "CLIENT_LABEL=${CLIENT_LABEL}"
  echo "APP_CONTAINER=${APP_CONTAINER:-}"
  echo "APP_METRICS_PORT=${APP_METRICS_PORT:-}"
} > "$ENV_FILE"
chmod 600 "$ENV_FILE"

sp::docker::ensure_network rede_publica
docker stack deploy -c "${SP_TEMPLATES_DIR}/compose/remote-agent.yml" "$SLUG"
# prometheus-agent/promtail só recebem config via bind mount — sem isso, uma
# mudança em --update que não altere a spec do serviço (ex: só o conteúdo do
# .yml) fica presa no container antigo, rodando config desatualizada.
sp::docker::force_restart "${SLUG}_prometheus-agent" "${SLUG}_promtail"

sp::ok "Agente remoto implantado. Métricas/logs deste servidor (label client=${CLIENT_LABEL}) começarão a aparecer no Grafana central em instantes."
if [[ -n "${APP_CONTAINER:-}" ]]; then
  sp::ok "Scrape de métricas da app '${APP_CONTAINER}:${APP_METRICS_PORT}' configurado (job_name=app)."
else
  sp::warn "Nenhuma app configurada para scrape de métricas. Rode de novo com --update pra adicionar."
fi
sp::log "INSTALL" "$SLUG" "client_label=${CLIENT_LABEL} central=${CENTRAL_INGEST_DOMAIN} app_container=${APP_CONTAINER:-none}"
