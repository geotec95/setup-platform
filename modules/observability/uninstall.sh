#!/bin/bash
# modules/observability/uninstall.sh — remove a stack, preservando os dados
# em /data/observability por padrão (métricas/logs/dashboards históricos).
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"

SLUG="observability"
DATA_DIR="${SP_DATA_ROOT}/${SLUG}"

sp::confirm "Remover a stack ${SLUG}? Os dados em ${DATA_DIR} serão preservados." && \
  sp::docker::remove_stack "$SLUG"

# Apagar dados é destrutivo (perde histórico de métricas/logs e dashboards
# customizados no Grafana) — por isso é uma pergunta separada, default "não".
if [[ -d "$DATA_DIR" ]]; then
  if sp::confirm "Apagar também os dados em ${DATA_DIR} (irreversível)?"; then
    rm -rf "$DATA_DIR"
    sp::ok "Dados de ${SLUG} removidos."
  else
    sp::info "Dados preservados em ${DATA_DIR}."
  fi
fi
