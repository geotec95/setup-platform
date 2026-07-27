#!/bin/bash
# providers/aws/route53.sh — helper para manter registro DNS A apontado para o IP
# público atual da instância (útil quando não há Elastic IP e o IP muda em stop/start).
#
# Uso:
#   source providers/aws/route53.sh
#   sp::aws::route53_upsert <zona_id> <subdominio> <ip> [ttl=300]
set -Eeuo pipefail

SP_ROOT="${SP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "${SP_ROOT}/core/common.sh"

sp::aws::_route53_check_prereqs() {
  sp::has_cmd aws || { sp::err "AWS CLI não encontrado."; return 1; }
  sp::has_cmd jq  || { sp::err "jq não encontrado."; return 1; }
  return 0
}

# sp::aws::route53_upsert <zona_id> <subdominio> <ip> [ttl]
# UPSERT é idempotente por natureza na API do Route53: reexecutar com o mesmo IP
# não gera efeito colateral (apenas confirma o estado desejado).
sp::aws::route53_upsert() {
  local zone_id="$1" record_name="$2" ip="$3" ttl="${4:-300}"

  sp::aws::_route53_check_prereqs || return 1
  [[ -n "$zone_id" ]] || { sp::err "ROUTE53_ZONE_ID não informado."; return 1; }
  [[ -n "$record_name" ]] || { sp::err "Nome do registro (subdomínio) não informado."; return 1; }
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { sp::err "IP inválido: ${ip}"; return 1; }

  # Route53 exige o nome do registro terminado em ponto (FQDN) na comparação exata,
  # mas aceita sem ponto na requisição — normalizamos aqui para evitar duplicidade.
  local change_batch
  change_batch="$(jq -n \
    --arg name "$record_name" --arg ip "$ip" --argjson ttl "$ttl" \
    '{
      Comment: "Atualizado automaticamente por setup-platform (sp::aws::route53_upsert)",
      Changes: [{
        Action: "UPSERT",
        ResourceRecordSet: {
          Name: $name,
          Type: "A",
          TTL: $ttl,
          ResourceRecords: [{ Value: $ip }]
        }
      }]
    }')"

  local change_id
  change_id="$(aws route53 change-resource-record-sets \
    --hosted-zone-id "$zone_id" \
    --change-batch "$change_batch" \
    --query 'ChangeInfo.Id' --output text)"

  sp::ok "Registro A ${record_name} -> ${ip} enviado ao Route53 (change: ${change_id})."
  sp::log "INFO" "aws-route53" "upsert ${record_name} -> ${ip} zone=${zone_id} change=${change_id}"
}

# Verifica se o registro atual já aponta para o IP informado (evita chamada de UPSERT
# desnecessária em execuções agendadas frequentes).
sp::aws::route53_current_ip() {
  local zone_id="$1" record_name="$2"
  aws route53 list-resource-record-sets --hosted-zone-id "$zone_id" \
    --query "ResourceRecordSets[?Name=='${record_name}.' && Type=='A'].ResourceRecords[0].Value" \
    --output text 2>/dev/null
}

# Wrapper idempotente de alto nível: só chama a API se o IP mudou.
sp::aws::route53_sync_if_changed() {
  local zone_id="$1" record_name="$2" ip="$3" ttl="${4:-300}"
  local current
  current="$(sp::aws::route53_current_ip "$zone_id" "$record_name" || true)"
  if [[ "$current" == "$ip" ]]; then
    sp::log "INFO" "aws-route53" "IP inalterado (${ip}), nenhuma atualização necessária."
    return 0
  fi
  sp::aws::route53_upsert "$zone_id" "$record_name" "$ip" "$ttl"
}
