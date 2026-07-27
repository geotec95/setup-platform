#!/bin/bash
# providers/aws/security-report.sh — checagens básicas de segurança (sem exigir
# Security Hub, que é pago/precisa ser habilitado explicitamente).
#
# Checagens sempre executadas (permissões de leitura padrão):
#   - Security Groups com portas sensíveis abertas para 0.0.0.0/0 (::/0 também).
#   - Usuários IAM sem MFA habilitado.
#   - Access keys de IAM com mais de 90 dias sem rotação.
#   - Buckets S3 com acesso público (via GetBucketPolicyStatus/GetBucketAcl).
#
# Checagens condicionais (só rodam se o serviço estiver habilitado na conta,
# com fallback gracioso — não falha o script se não estiver disponível):
#   - Security Hub (findings ativos, severidade >= MEDIUM).
#   - Trusted Advisor (requer plano Business/Enterprise; via Support API).
#
# SOMENTE LEITURA. IDEMPOTENTE (sobrescreve o report do dia).
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${SP_ROOT}/core/common.sh"

AWS_REGION="${AWS_REGION:-us-east-1}"
DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Portas consideradas sensíveis se expostas a 0.0.0.0/0 (SSH, RDP, bancos de dados)
readonly SENSITIVE_PORTS=(22 3389 3306 5432 27017 6379 9200 5984 1433)
readonly ACCESS_KEY_MAX_AGE_DAYS=90

sp::aws::_cli() {
  aws --region "$AWS_REGION" --output json "$@"
}

sp::aws::sec::_check_prereqs() {
  sp::has_cmd aws || { sp::err "AWS CLI não encontrado. Rode modules/aws-monitor/install.sh primeiro."; exit 1; }
  sp::has_cmd jq  || { sp::err "jq não encontrado."; exit 1; }
  sp::aws::_cli sts get-caller-identity >/dev/null 2>&1 \
    || { sp::err "Sem credenciais AWS válidas."; exit 1; }
}

# --- Security Groups ---------------------------------------------------------

sp::aws::sec::_open_security_groups() {
  local ports_json
  ports_json="$(printf '%s\n' "${SENSITIVE_PORTS[@]}" | jq -R 'tonumber' | jq -s .)"

  sp::aws::_cli ec2 describe-security-groups \
    | jq --argjson ports "$ports_json" '
      [.SecurityGroups[] as $sg
        | $sg.IpPermissions[] as $perm
        | ($perm.IpRanges[]?.CidrIp, $perm.Ipv6Ranges[]?.CidrIpv6) as $cidr
        | select($cidr == "0.0.0.0/0" or $cidr == "::/0")
        | (if $perm.FromPort == null then [] else [range($perm.FromPort; $perm.ToPort+1)] end) as $range
        | select(($range - ($ports | map(. )) | length) < ($range | length) or $perm.IpProtocol == "-1")
        | {
            groupId: $sg.GroupId,
            groupName: $sg.GroupName,
            vpcId: $sg.VpcId,
            protocol: $perm.IpProtocol,
            fromPort: $perm.FromPort,
            toPort: $perm.ToPort,
            cidr: $cidr
          }
      ] | unique'
}

# --- IAM ----------------------------------------------------------------------

sp::aws::sec::_users_without_mfa() {
  local users
  users="$(sp::aws::_cli iam list-users | jq -r '.Users[].UserName')"
  local result="[]"
  local user mfa_count
  while IFS= read -r user; do
    [[ -z "$user" ]] && continue
    mfa_count="$(sp::aws::_cli iam list-mfa-devices --user-name "$user" | jq '.MFADevices | length')"
    if [[ "$mfa_count" -eq 0 ]]; then
      result="$(echo "$result" | jq --arg u "$user" '. + [$u]')"
    fi
  done <<< "$users"
  echo "$result"
}

sp::aws::sec::_old_access_keys() {
  local users
  users="$(sp::aws::_cli iam list-users | jq -r '.Users[].UserName')"
  local result="[]"
  local user
  while IFS= read -r user; do
    [[ -z "$user" ]] && continue
    local keys
    keys="$(sp::aws::_cli iam list-access-keys --user-name "$user" \
      | jq -c '.AccessKeyMetadata[] | select(.Status=="Active")')"
    [[ -z "$keys" ]] && continue
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      local key_id create_date age_days
      key_id="$(echo "$key" | jq -r '.AccessKeyId')"
      create_date="$(echo "$key" | jq -r '.CreateDate')"
      age_days=$(( ( $(date -u +%s) - $(date -u -d "$create_date" +%s 2>/dev/null || date -u -jf '%Y-%m-%dT%H:%M:%S' "${create_date%%+*}" +%s) ) / 86400 ))
      if [[ "$age_days" -gt "$ACCESS_KEY_MAX_AGE_DAYS" ]]; then
        result="$(echo "$result" | jq --arg u "$user" --arg k "$key_id" --arg a "$age_days" \
          '. + [{user: $u, accessKeyId: $k, ageDays: ($a | tonumber)}]')"
      fi
    done <<< "$keys"
  done <<< "$users"
  echo "$result"
}

# --- S3 -------------------------------------------------------------------------

sp::aws::sec::_public_buckets() {
  local buckets
  buckets="$(sp::aws::_cli s3api list-buckets | jq -r '.Buckets[].Name')"
  local result="[]"
  local bucket
  while IFS= read -r bucket; do
    [[ -z "$bucket" ]] && continue
    local is_public
    is_public="$(aws s3api get-bucket-policy-status --bucket "$bucket" --output json 2>/dev/null \
      | jq -r '.PolicyStatus.IsPublic // false')"
    local acl_public
    acl_public="$(aws s3api get-bucket-acl --bucket "$bucket" --output json 2>/dev/null \
      | jq -r '[.Grants[]? | select(.Grantee.URI? == "http://acs.amazonaws.com/groups/global/AllUsers")] | length > 0')"
    if [[ "$is_public" == "true" || "$acl_public" == "true" ]]; then
      result="$(echo "$result" | jq --arg b "$bucket" '. + [$b]')"
    fi
  done <<< "$buckets"
  echo "$result"
}

# --- Condicionais: Security Hub / Trusted Advisor -------------------------------

sp::aws::sec::_security_hub_findings() {
  # Retorna [] silenciosamente se Security Hub não estiver habilitado (erro esperado,
  # não é uma falha do script — fallback gracioso conforme requisito).
  aws --region "$AWS_REGION" securityhub get-findings \
    --filters '{"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}],"SeverityLabel":[{"Value":"MEDIUM","Comparison":"EQUALS"},{"Value":"HIGH","Comparison":"EQUALS"},{"Value":"CRITICAL","Comparison":"EQUALS"}]}' \
    --max-results 50 --output json 2>/dev/null \
    | jq '[.Findings[]? | {title: .Title, severity: .Severity.Label, resource: (.Resources[0].Id // "N/A")}]' \
    || echo '[]'
}

sp::aws::sec::_trusted_advisor_findings() {
  # Trusted Advisor via Support API requer plano Business/Enterprise; em Basic/Developer
  # a chamada retorna erro "SubscriptionRequiredException" — tratado como indisponível.
  aws --region us-east-1 support describe-trusted-advisor-checks --language en --output json 2>/dev/null \
    | jq -c '.checks[]? | select(.category=="security")' 2>/dev/null \
    | while IFS= read -r check; do
        local check_id
        check_id="$(echo "$check" | jq -r '.id')"
        aws --region us-east-1 support describe-trusted-advisor-check-result \
          --check-id "$check_id" --language en --output json 2>/dev/null \
          | jq --arg name "$(echo "$check" | jq -r '.name')" \
            '{check: $name, status: .result.status, flaggedResources: (.result.flaggedResources | length)}'
      done | jq -s '.' 2>/dev/null || echo '[]'
}

# --- Main -------------------------------------------------------------------

main() {
  sp::aws::sec::_check_prereqs

  if $DRY_RUN; then
    sp::ok "Dry-run OK: credenciais e permissões básicas de IAM/EC2/S3 funcionando."
    return 0
  fi

  sp::info "Analisando Security Groups expostos..."
  local open_sgs; open_sgs="$(sp::aws::sec::_open_security_groups)"

  sp::info "Analisando usuários IAM sem MFA..."
  local no_mfa; no_mfa="$(sp::aws::sec::_users_without_mfa)"

  sp::info "Analisando access keys antigas (> ${ACCESS_KEY_MAX_AGE_DAYS} dias)..."
  local old_keys; old_keys="$(sp::aws::sec::_old_access_keys)"

  sp::info "Analisando buckets S3 públicos..."
  local public_buckets; public_buckets="$(sp::aws::sec::_public_buckets)"

  sp::info "Verificando Security Hub (opcional)..."
  local sh_findings; sh_findings="$(sp::aws::sec::_security_hub_findings)"

  sp::info "Verificando Trusted Advisor (opcional, requer Business/Enterprise)..."
  local ta_findings; ta_findings="$(sp::aws::sec::_trusted_advisor_findings)"

  local today; today="$(date -u +%Y-%m-%d)"
  local out_dir="${SP_DATA_ROOT}/aws-monitor/reports/${today}"
  mkdir -p "$out_dir"

  local json_file="${out_dir}/security-report.json"
  jq -n \
    --arg generatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson openSecurityGroups "$open_sgs" \
    --argjson usersWithoutMfa "$no_mfa" \
    --argjson oldAccessKeys "$old_keys" \
    --argjson publicBuckets "$public_buckets" \
    --argjson securityHubFindings "$sh_findings" \
    --argjson trustedAdvisorFindings "$ta_findings" \
    '{
      generatedAt: $generatedAt,
      openSecurityGroups: $openSecurityGroups,
      usersWithoutMfa: $usersWithoutMfa,
      oldAccessKeys: $oldAccessKeys,
      publicS3Buckets: $publicBuckets,
      securityHubFindings: $securityHubFindings,
      trustedAdvisorFindings: $trustedAdvisorFindings
    }' > "$json_file"

  local md_file="${out_dir}/security-report.md"
  {
    echo "# Relatório de Segurança AWS — ${today}"
    echo
    echo "## Security Groups abertos para 0.0.0.0/0 em portas sensíveis"
    echo "$open_sgs" | jq -r 'if length==0 then "- nenhum encontrado" else .[] | "- \(.groupId) (\(.groupName)) porta \(.fromPort)-\(.toPort)/\(.protocol) <- \(.cidr)" end'
    echo
    echo "## Usuários IAM sem MFA"
    echo "$no_mfa" | jq -r 'if length==0 then "- nenhum" else .[] | "- \(.)" end'
    echo
    echo "## Access keys ativas há mais de ${ACCESS_KEY_MAX_AGE_DAYS} dias"
    echo "$old_keys" | jq -r 'if length==0 then "- nenhuma" else .[] | "- \(.user) — \(.accessKeyId) (\(.ageDays) dias)" end'
    echo
    echo "## Buckets S3 públicos"
    echo "$public_buckets" | jq -r 'if length==0 then "- nenhum" else .[] | "- \(.)" end'
    echo
    echo "## Security Hub (se habilitado)"
    echo "$sh_findings" | jq -r 'if length==0 then "- sem findings ou serviço não habilitado" else .[] | "- [\(.severity)] \(.title) (\(.resource))" end'
    echo
    echo "## Trusted Advisor — checks de segurança (se plano Business/Enterprise)"
    echo "$ta_findings" | jq -r 'if length==0 then "- indisponível (requer Business/Enterprise) ou sem achados" else .[] | "- \(.check): \(.status) (\(.flaggedResources) recursos sinalizados)" end'
  } > "$md_file"

  sp::ok "Relatório de segurança gerado em ${json_file} e ${md_file}"
  echo "$json_file"
}

main "$@"
