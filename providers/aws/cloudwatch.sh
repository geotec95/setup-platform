#!/bin/bash
# providers/aws/cloudwatch.sh — helpers CloudWatch (logs, métricas e alarmes básicos).
#
# Uso:
#   source providers/aws/cloudwatch.sh
#   sp::aws::cw_ensure_log_group <nome> [retencao_dias=30]
#   sp::aws::cw_put_metric <namespace> <metrica> <valor> [unidade=None] [dimensoes]
#   sp::aws::cw_put_alarm <nome> <metrica> <namespace> <threshold> <comparador> <acao_arn>
set -Eeuo pipefail

SP_ROOT="${SP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "${SP_ROOT}/core/common.sh"

AWS_REGION="${AWS_REGION:-us-east-1}"

sp::aws::_cw_check_prereqs() {
  sp::has_cmd aws || { sp::err "AWS CLI não encontrado."; return 1; }
  return 0
}

# sp::aws::cw_ensure_log_group <nome> [retencao_dias]
# Idempotente: create-log-group falha silenciosamente (ResourceAlreadyExistsException)
# se o grupo já existir — tratado como sucesso.
sp::aws::cw_ensure_log_group() {
  local name="$1" retention="${2:-30}"
  sp::aws::_cw_check_prereqs || return 1

  if aws --region "$AWS_REGION" logs describe-log-groups \
      --log-group-name-prefix "$name" \
      --query "logGroups[?logGroupName=='${name}']" --output text 2>/dev/null | grep -q .; then
    sp::log "INFO" "aws-cloudwatch" "Log group '${name}' já existe."
  else
    aws --region "$AWS_REGION" logs create-log-group --log-group-name "$name"
    sp::ok "Log group '${name}' criado."
  fi

  aws --region "$AWS_REGION" logs put-retention-policy \
    --log-group-name "$name" --retention-in-days "$retention" >/dev/null 2>&1 || true
}

# sp::aws::cw_put_metric <namespace> <metrica> <valor> [unidade] [dimensoes="Chave=Valor,Chave2=Valor2"]
sp::aws::cw_put_metric() {
  local namespace="$1" metric="$2" value="$3" unit="${4:-None}" dimensions="${5:-}"
  sp::aws::_cw_check_prereqs || return 1

  local args=(cloudwatch put-metric-data --region "$AWS_REGION"
    --namespace "$namespace" --metric-name "$metric" --value "$value" --unit "$unit")

  if [[ -n "$dimensions" ]]; then
    local dim_json="["
    local first=true
    IFS=',' read -ra pairs <<< "$dimensions"
    for pair in "${pairs[@]}"; do
      local k="${pair%%=*}" v="${pair#*=}"
      $first || dim_json+=","
      dim_json+="{\"Name\":\"${k}\",\"Value\":\"${v}\"}"
      first=false
    done
    dim_json+="]"
    args+=(--dimensions "$dim_json")
  fi

  aws "${args[@]}" >/dev/null
  sp::log "INFO" "aws-cloudwatch" "Métrica publicada: ${namespace}/${metric}=${value}${unit:+ ${unit}}"
}

# sp::aws::cw_put_alarm <nome> <metrica> <namespace> <threshold> <comparador> [acao_arn] [periodo=300] [estatistica=Average]
# comparador: GreaterThanThreshold | LessThanThreshold | GreaterThanOrEqualToThreshold | etc.
# Idempotente: put-metric-alarm sobrescreve o alarme existente com o mesmo nome.
sp::aws::cw_put_alarm() {
  local name="$1" metric="$2" namespace="$3" threshold="$4" comparator="$5"
  local action_arn="${6:-}" period="${7:-300}" statistic="${8:-Average}"

  sp::aws::_cw_check_prereqs || return 1

  local args=(cloudwatch put-metric-alarm --region "$AWS_REGION"
    --alarm-name "$name"
    --metric-name "$metric"
    --namespace "$namespace"
    --statistic "$statistic"
    --period "$period"
    --threshold "$threshold"
    --comparison-operator "$comparator"
    --evaluation-periods 1
  )
  [[ -n "$action_arn" ]] && args+=(--alarm-actions "$action_arn")

  aws "${args[@]}"
  sp::ok "Alarme CloudWatch '${name}' configurado (${metric} ${comparator} ${threshold})."
}

# Atalho de alto nível: cria alarme de custo estimado da conta (billing).
# Requer que o billing alert esteja habilitado na conta (Billing Preferences).
sp::aws::cw_put_billing_alarm() {
  local threshold_usd="$1" action_arn="${2:-}"
  sp::aws::cw_put_alarm \
    "aws-monitor-custo-estimado" \
    "EstimatedCharges" \
    "AWS/Billing" \
    "$threshold_usd" \
    "GreaterThanThreshold" \
    "$action_arn" \
    21600 \
    "Maximum"
}
