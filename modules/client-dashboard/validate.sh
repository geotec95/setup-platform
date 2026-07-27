#!/bin/bash
# modules/client-dashboard/validate.sh — validação pós-instalação.
# Sem argumento: valida a base do módulo (dependências) e lista clientes ativos.
# Com argumento <slug-cliente>: valida especificamente aquele cliente (stack +
# HTTPS respondendo).
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"

FAIL=0

if ! docker stack ls --format '{{.Name}}' 2>/dev/null | grep -qx "observability"; then
  echo "observability: FAIL (dependência ausente)"
  FAIL=1
else
  echo "observability: OK"
fi

CLIENT_SLUG="${1:-}"

validate_client() {
  local slug="$1" client_dir="${SP_MODULES_DIR}/client-dashboard/clients/${slug}"
  if [[ ! -f "${client_dir}/.env" ]]; then
    echo "cliente ${slug}: FAIL (não provisionado)"
    FAIL=1
    return
  fi
  # shellcheck disable=SC1090
  set -a; source "${client_dir}/.env"; set +a

  if docker stack services "clientdash-${slug}" >/dev/null 2>&1; then
    echo "cliente ${slug} (stack clientdash-${slug}): OK"
  else
    echo "cliente ${slug} (stack clientdash-${slug}): FAIL"
    FAIL=1
  fi

  if [[ -n "${CLIENT_DOMAIN:-}" ]]; then
    code="$(curl -ksS -o /dev/null -w '%{http_code}' "https://${CLIENT_DOMAIN}" || echo 000)"
    if [[ "$code" =~ ^(200|301|302)$ ]]; then
      echo "cliente ${slug} (https://${CLIENT_DOMAIN}): OK (${code})"
    else
      echo "cliente ${slug} (https://${CLIENT_DOMAIN}): FAIL (${code})"
      FAIL=1
    fi
  fi
}

if [[ -n "$CLIENT_SLUG" ]]; then
  validate_client "$CLIENT_SLUG"
else
  shopt -s nullglob
  for env_file in "${SP_MODULES_DIR}/client-dashboard/clients"/*/.env; do
    slug="$(basename "$(dirname "$env_file")")"
    validate_client "$slug"
  done
  shopt -u nullglob
fi

exit "$FAIL"
