#!/bin/bash
# modules/aws-monitor/validate.sh — verificação pós-instalação do AWS Monitor.
# Checa: .env presente, scripts staged e executáveis, AWS CLI/jq disponíveis,
# credenciais válidas (dry-run dos scripts de report).
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${SP_ROOT}/core/common.sh"

SLUG="aws-monitor"
ENV_FILE="${SP_ROOT}/modules/${SLUG}/.env"
BIN_DIR="${SP_DATA_ROOT}/${SLUG}/bin"
FAIL=0

check() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then
    echo "aws-monitor: OK — ${desc}"
  else
    echo "aws-monitor: FAIL — ${desc}"
    FAIL=1
  fi
}

check "arquivo .env presente" test -f "$ENV_FILE"
check "AWS CLI instalado" sp::has_cmd aws
check "jq instalado" sp::has_cmd jq
check "script cost-report.sh staged e executável" test -x "${BIN_DIR}/cost-report.sh"
check "script security-report.sh staged e executável" test -x "${BIN_DIR}/security-report.sh"

# shellcheck disable=SC1090
set -a; source "$ENV_FILE" 2>/dev/null || true; set +a
check "credenciais AWS válidas (sts get-caller-identity)" aws sts get-caller-identity

if [[ "$FAIL" -eq 0 ]]; then
  echo "aws-monitor: TODAS AS VERIFICAÇÕES OK"
else
  echo "aws-monitor: FALHOU EM UMA OU MAIS VERIFICAÇÕES"
fi
exit "$FAIL"
