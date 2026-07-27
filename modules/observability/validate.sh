#!/bin/bash
# modules/observability/validate.sh — checagem pós-instalação: confere se
# todos os containers da stack subiram e se o Grafana responde no /api/health.
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"

SLUG="observability"
SERVICES=(grafana prometheus loki promtail cadvisor node-exporter)
FAIL=0

for svc in "${SERVICES[@]}"; do
  if docker ps --format '{{.Names}}' | grep -q "^${SLUG}_${svc}"; then
    sp::ok "${svc}: container em execução."
  else
    sp::err "${svc}: container não encontrado/rodando."
    FAIL=1
  fi
done

# Healthcheck HTTP do Grafana (único serviço com endpoint acessível localmente
# via rede overlay a partir do host, quando publicado por porta; aqui
# validamos via `docker exec` para não depender de exposição no host).
GRAFANA_CID="$(docker ps --format '{{.ID}} {{.Names}}' | awk -v n="^${SLUG}_grafana" '$0 ~ n {print $1; exit}')"
if [[ -n "$GRAFANA_CID" ]]; then
  if docker exec "$GRAFANA_CID" wget -qO- http://localhost:3000/api/health >/dev/null 2>&1; then
    sp::ok "Grafana: /api/health respondendo."
  else
    sp::err "Grafana: /api/health não respondeu."
    FAIL=1
  fi
else
  sp::warn "Não foi possível localizar o container do Grafana para checar /api/health."
fi

if [[ "$FAIL" -eq 0 ]]; then
  sp::ok "${SLUG}: todos os componentes saudáveis."
  exit 0
else
  sp::err "${SLUG}: um ou mais componentes falharam na validação."
  exit 1
fi
