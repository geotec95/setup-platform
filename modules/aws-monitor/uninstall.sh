#!/bin/bash
# modules/aws-monitor/uninstall.sh — remove o AWS Monitor / FinOps Agent.
#
# Estratégia: este módulo não sobe stack Docker própria (é headless, roda via n8n +
# AWS CLI), então "desinstalar" significa remover os scripts staged e o .env local.
# Os reports já gerados em /data/aws-monitor/reports ficam preservados por padrão
# (histórico útil), removidos apenas com confirmação explícita.
# O workflow no n8n precisa ser removido manualmente pelo usuário (evita apagar
# customizações que o usuário tenha feito no workflow importado).
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${SP_ROOT}/core/common.sh"

SLUG="aws-monitor"
DATA_DIR="${SP_DATA_ROOT}/${SLUG}"
ENV_FILE="${SP_ROOT}/modules/${SLUG}/.env"

if [[ ! -f "$ENV_FILE" && ! -d "$DATA_DIR" ]]; then
  sp::warn "${SLUG} não parece estar instalado."
  exit 0
fi

sp::confirm "Remover configuração do AWS Monitor (${ENV_FILE} e scripts staged)?" && {
  rm -f "$ENV_FILE"
  rm -rf "${DATA_DIR}/bin"
  sp::ok "Configuração e scripts removidos."
}

if [[ -d "${DATA_DIR}/reports" ]]; then
  sp::confirm "Remover também o histórico de reports gerados (${DATA_DIR}/reports)? Isso é irreversível." && {
    rm -rf "${DATA_DIR}/reports"
    sp::ok "Histórico de reports removido."
  }
fi

sp::warn "Lembrete: remova/desative manualmente o workflow 'AWS FinOps Report' no n8n"
sp::warn "(Workflows -> AWS FinOps Report -> Delete), se não for mais usá-lo."
sp::warn "Se anexou a IAM Role via Instance Profile só para este agente, considere removê-la"
sp::warn "(providers/aws/iam-policy-aws-monitor.json) caso nenhum outro módulo dependa dela."

sp::log "UNINSTALL" "$SLUG" "executado"
