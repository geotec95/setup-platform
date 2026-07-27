#!/bin/bash
# modules/client-dashboard/remove-client.sh — remove um cliente provisionado
# por new-client.sh: a Organization no Grafana compartilhado, o container do
# wrapper estático e, opcionalmente (mediante confirmação), os dados/credenciais
# locais em modules/client-dashboard/clients/<slug>.
#
# Uso: bash remove-client.sh <slug-cliente>
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"

CLIENT_SLUG="${1:-}"
[[ -z "$CLIENT_SLUG" ]] && { sp::err "Uso: bash remove-client.sh <slug-cliente>"; exit 1; }

MODULE_DIR="${SP_MODULES_DIR}/client-dashboard"
CLIENT_DIR="${MODULE_DIR}/clients/${CLIENT_SLUG}"
STACK_NAME="clientdash-${CLIENT_SLUG}"

if [[ ! -f "${CLIENT_DIR}/.env" ]]; then
  sp::warn "Cliente '${CLIENT_SLUG}' não encontrado em ${CLIENT_DIR}. Nada a fazer."
  exit 0
fi

# shellcheck disable=SC1091
set -a; source "${CLIENT_DIR}/.env"; set +a

sp::confirm "Remover o container/stack do dashboard de '${CLIENT_NAME:-$CLIENT_SLUG}' (${STACK_NAME})?" && \
  sp::docker::remove_stack "$STACK_NAME"

if [[ -n "${CLIENT_GRAFANA_ORG_ID:-}" ]]; then
  sp::confirm "Remover também a Organization (id=${CLIENT_GRAFANA_ORG_ID}) e o usuário '${CLIENT_GRAFANA_VIEWER_USER:-}' no Grafana compartilhado? Isso apaga os dashboards do cliente." && {
    OBS_ENV="${SP_MODULES_DIR}/observability/.env"
    if [[ -f "$OBS_ENV" ]]; then
      # shellcheck disable=SC1090
      set -a; source "$OBS_ENV"; set +a
      GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"

      if [[ -n "${GRAFANA_BASE_URL:-}" && -n "${GRAFANA_ADMIN_PASSWORD:-}" ]]; then
        curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
          -X DELETE "${GRAFANA_BASE_URL}/api/orgs/${CLIENT_GRAFANA_ORG_ID}" \
          && sp::ok "Organization ${CLIENT_GRAFANA_ORG_ID} removida." \
          || sp::warn "Falha ao remover a Organization no Grafana (verifique manualmente)."

        if [[ -n "${CLIENT_GRAFANA_VIEWER_USER:-}" ]]; then
          LOOKUP_JSON="$(curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
            "${GRAFANA_BASE_URL}/api/users/lookup?loginOrEmail=${CLIENT_GRAFANA_VIEWER_USER}" || true)"
          VIEWER_USER_ID="$(echo "${LOOKUP_JSON:-{}}" | jq -r '.id // empty')"
          if [[ -n "$VIEWER_USER_ID" ]]; then
            curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
              -X DELETE "${GRAFANA_BASE_URL}/api/admin/users/${VIEWER_USER_ID}" \
              && sp::ok "Usuário '${CLIENT_GRAFANA_VIEWER_USER}' removido." \
              || sp::warn "Falha ao remover o usuário no Grafana (verifique manualmente)."
          fi
        fi
      else
        sp::warn "Credenciais do admin do Grafana indisponíveis — remova a Organization manualmente."
      fi
    else
      sp::warn "modules/observability/.env não encontrado — remova a Organization manualmente."
    fi
  }
fi

sp::confirm "Apagar também os dados locais (${CLIENT_DIR} e /data/client-dashboard/${CLIENT_SLUG})? Isso é IRREVERSÍVEL." && {
  rm -rf "$CLIENT_DIR"
  rm -rf "${SP_DATA_ROOT}/client-dashboard/${CLIENT_SLUG}"
  sp::ok "Dados locais do cliente '${CLIENT_SLUG}' removidos."
}

sp::log "REMOVE_CLIENT" "client-dashboard" "slug=${CLIENT_SLUG}"
sp::ok "Remoção do cliente '${CLIENT_SLUG}' concluída."
