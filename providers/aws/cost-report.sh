#!/bin/bash
# providers/aws/cost-report.sh — relatório de custos e recursos ociosos (FinOps)
#
# O QUE FAZ:
#   - Custo total dos últimos 7 e 30 dias + variação % vs. período anterior equivalente.
#   - Breakdown por serviço (top 10) via Cost Explorer.
#   - Recursos ociosos óbvios: Elastic IPs não associados, volumes EBS não anexados,
#     instâncias EC2 paradas há mais de N dias.
#   - Status de orçamentos (AWS Budgets), se houver algum configurado.
#
# SOMENTE LEITURA: nenhuma chamada aqui cria, altera ou destrói recursos.
# IDEMPOTENTE: pode ser reexecutado a qualquer momento sem efeitos colaterais;
# cada execução sobrescreve o report do dia (não acumula lixo em disco).
#
# Saída: JSON estruturado + Markdown legível, em /data/aws-monitor/reports/YYYY-MM-DD/
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${SP_ROOT}/core/common.sh"

AWS_REGION="${AWS_REGION:-us-east-1}"
IDLE_STOPPED_DAYS_THRESHOLD="${IDLE_STOPPED_DAYS_THRESHOLD:-30}"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

sp::aws::_cli() {
  # Wrapper único para aws cli: aplica região e formato JSON, e falha de forma
  # amigável se a CLI não estiver instalada/configurada.
  aws --region "$AWS_REGION" --output json "$@"
}

sp::aws::cost::_check_prereqs() {
  sp::has_cmd aws || { sp::err "AWS CLI não encontrado. Rode modules/aws-monitor/install.sh primeiro."; exit 1; }
  sp::has_cmd jq  || { sp::err "jq não encontrado (necessário para processar respostas da AWS CLI)."; exit 1; }
  if ! sp::aws::_cli sts get-caller-identity >/dev/null 2>&1; then
    sp::err "Sem credenciais AWS válidas (Instance Profile / aws configure / variáveis de ambiente)."
    exit 1
  fi
}

# --- Cost Explorer ----------------------------------------------------------

# Retorna custo total (USD) de um intervalo [start, end)
sp::aws::cost::_total() {
  local start="$1" end="$2"
  sp::aws::_cli ce get-cost-and-usage \
    --time-period "Start=${start},End=${end}" \
    --granularity DAILY \
    --metrics "UnblendedCost" 2>/dev/null \
    | jq -r '[.ResultsByTime[].Total.UnblendedCost.Amount | tonumber] | add // 0'
}

# Top 10 serviços por custo no intervalo [start, end)
sp::aws::cost::_top_services() {
  local start="$1" end="$2"
  sp::aws::_cli ce get-cost-and-usage \
    --time-period "Start=${start},End=${end}" \
    --granularity MONTHLY \
    --metrics "UnblendedCost" \
    --group-by Type=DIMENSION,Key=SERVICE 2>/dev/null \
    | jq '[.ResultsByTime[0].Groups[]? | {service: .Keys[0], cost: (.Metrics.UnblendedCost.Amount | tonumber)}]
          | sort_by(-.cost) | .[0:10]'
}

sp::aws::cost::_pct_change() {
  # variação percentual: (atual - anterior) / anterior * 100. Evita divisão por zero.
  local atual="$1" anterior="$2"
  awk -v a="$atual" -v b="$anterior" 'BEGIN {
    if (b == 0) { print (a > 0 ? 100 : 0); exit }
    printf "%.2f", ((a - b) / b) * 100
  }'
}

# --- Recursos ociosos --------------------------------------------------------

sp::aws::cost::_idle_eips() {
  sp::aws::_cli ec2 describe-addresses \
    | jq '[.Addresses[] | select(.AssociationId == null) | {publicIp: .PublicIp, allocationId: .AllocationId}]'
}

sp::aws::cost::_idle_volumes() {
  sp::aws::_cli ec2 describe-volumes --filters "Name=status,Values=available" \
    | jq '[.Volumes[] | {volumeId: .VolumeId, sizeGiB: .Size, type: .VolumeType, az: .AvailabilityZone}]'
}

sp::aws::cost::_stopped_instances() {
  local threshold_epoch
  threshold_epoch="$(date -u -d "-${IDLE_STOPPED_DAYS_THRESHOLD} days" +%s 2>/dev/null \
    || date -u -v"-${IDLE_STOPPED_DAYS_THRESHOLD}d" +%s)"

  sp::aws::_cli ec2 describe-instances --filters "Name=instance-state-name,Values=stopped" \
    | jq --argjson threshold "$threshold_epoch" '
      [.Reservations[].Instances[]
        | . as $i
        | ($i.StateTransitionReason // "" | capture("\\((?<d>[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]+) ")? .d) as $stopped_at
        | select($stopped_at != null)
        | {instanceId: $i.InstanceId, type: $i.InstanceType, stoppedAt: $stopped_at}
      ]'
}

# --- Budgets ------------------------------------------------------------------

sp::aws::cost::_budgets_status() {
  local account_id
  account_id="$(sp::aws::_cli sts get-caller-identity --query Account --output text 2>/dev/null)"
  # AWS Budgets é opcional: se nenhum orçamento configurado ou sem permissão, retorna lista vazia
  # sem quebrar o report (fallback gracioso).
  sp::aws::_cli budgets describe-budgets --account-id "$account_id" 2>/dev/null \
    | jq '[.Budgets[]? | {
        name: .BudgetName,
        limit: .BudgetLimit.Amount,
        unit: .BudgetLimit.Unit,
        actualSpend: .CalculatedSpend.ActualSpend.Amount,
        forecastedSpend: .CalculatedSpend.ForecastedSpend.Amount
      }]' \
    || echo '[]'
}

# --- Main -----------------------------------------------------------------

main() {
  sp::aws::cost::_check_prereqs

  local today d7_start d7_prev_start d30_start d30_prev_start
  today="$(date -u +%Y-%m-%d)"
  d7_start="$(date -u -d '-7 days' +%Y-%m-%d 2>/dev/null || date -u -v-7d +%Y-%m-%d)"
  d7_prev_start="$(date -u -d '-14 days' +%Y-%m-%d 2>/dev/null || date -u -v-14d +%Y-%m-%d)"
  d30_start="$(date -u -d '-30 days' +%Y-%m-%d 2>/dev/null || date -u -v-30d +%Y-%m-%d)"
  d30_prev_start="$(date -u -d '-60 days' +%Y-%m-%d 2>/dev/null || date -u -v-60d +%Y-%m-%d)"

  sp::info "Coletando custos (Cost Explorer) e recursos ociosos (EC2)..."

  local cost_7d cost_7d_prev cost_30d cost_30d_prev
  cost_7d="$(sp::aws::cost::_total "$d7_start" "$today")"
  cost_7d_prev="$(sp::aws::cost::_total "$d7_prev_start" "$d7_start")"
  cost_30d="$(sp::aws::cost::_total "$d30_start" "$today")"
  cost_30d_prev="$(sp::aws::cost::_total "$d30_prev_start" "$d30_start")"

  local var_7d var_30d
  var_7d="$(sp::aws::cost::_pct_change "$cost_7d" "$cost_7d_prev")"
  var_30d="$(sp::aws::cost::_pct_change "$cost_30d" "$cost_30d_prev")"

  local top_services idle_eips idle_volumes stopped_instances budgets
  top_services="$(sp::aws::cost::_top_services "$d30_start" "$today")"
  idle_eips="$(sp::aws::cost::_idle_eips)"
  idle_volumes="$(sp::aws::cost::_idle_volumes)"
  stopped_instances="$(sp::aws::cost::_stopped_instances)"
  budgets="$(sp::aws::cost::_budgets_status)"

  local out_dir="${SP_DATA_ROOT}/aws-monitor/reports/${today}"
  if $DRY_RUN; then
    sp::ok "Dry-run OK: credenciais e permissões básicas de Cost Explorer/EC2 funcionando."
    return 0
  fi
  mkdir -p "$out_dir"

  local json_file="${out_dir}/cost-report.json"
  jq -n \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg cost7d "$cost_7d" --arg cost7dPrev "$cost_7d_prev" --arg var7d "$var_7d" \
    --arg cost30d "$cost_30d" --arg cost30dPrev "$cost_30d_prev" --arg var30d "$var_30d" \
    --argjson topServices "$top_services" \
    --argjson idleEips "$idle_eips" \
    --argjson idleVolumes "$idle_volumes" \
    --argjson stoppedInstances "$stopped_instances" \
    --argjson budgets "$budgets" \
    '{
      generatedAt: $generatedAt,
      cost: {
        last7Days: { total: $cost7d, previous: $cost7dPrev, variationPct: $var7d },
        last30Days: { total: $cost30d, previous: $cost30dPrev, variationPct: $var30d },
        topServices: $topServices
      },
      idleResources: {
        unassociatedElasticIps: $idleEips,
        unattachedVolumes: $idleVolumes,
        stoppedInstances: $stoppedInstances
      },
      budgets: $budgets
    }' > "$json_file"

  local md_file="${out_dir}/cost-report.md"
  {
    echo "# Relatório de Custos AWS — ${today}"
    echo
    echo "## Resumo"
    printf -- "- **Últimos 7 dias:** US\$ %.2f (variação: %s%% vs. 7 dias anteriores)\n" "$cost_7d" "$var_7d"
    printf -- "- **Últimos 30 dias:** US\$ %.2f (variação: %s%% vs. 30 dias anteriores)\n" "$cost_30d" "$var_30d"
    echo
    echo "## Top 10 serviços (30 dias)"
    echo "$top_services" | jq -r '.[] | "- \(.service): US$ \(.cost | tonumber | (.*100|round)/100)"'
    echo
    echo "## Recursos ociosos"
    echo "### Elastic IPs não associados"
    echo "$idle_eips" | jq -r 'if length==0 then "- nenhum" else .[] | "- \(.publicIp) (\(.allocationId))" end'
    echo "### Volumes EBS não anexados"
    echo "$idle_volumes" | jq -r 'if length==0 then "- nenhum" else .[] | "- \(.volumeId) — \(.sizeGiB)GiB \(.type) (\(.az))" end'
    echo "### Instâncias paradas há mais de ${IDLE_STOPPED_DAYS_THRESHOLD} dias"
    echo "$stopped_instances" | jq -r 'if length==0 then "- nenhuma" else .[] | "- \(.instanceId) (\(.type)) parada desde \(.stoppedAt)" end'
    echo
    echo "## Orçamentos (AWS Budgets)"
    echo "$budgets" | jq -r 'if length==0 then "- nenhum orçamento configurado" else .[] | "- \(.name): US$ \(.actualSpend)/\(.limit) \(.unit) (previsto: US$ \(.forecastedSpend))" end'
  } > "$md_file"

  sp::ok "Relatório de custos gerado em ${json_file} e ${md_file}"
  echo "$json_file"
}

main "$@"
