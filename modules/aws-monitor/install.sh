#!/bin/bash
# modules/aws-monitor/install.sh — instala o AWS Monitor / FinOps Agent.
#
# Passos (seguindo o padrão de modules/n8n/install.sh):
#   1) checa idempotência (não reinstala se já configurado, exceto --update)
#   2) garante AWS CLI + jq instalados
#   3) valida credenciais (Instance Profile > aws configure > variáveis de ambiente)
#   4) gera .env do módulo a partir do template
#   5) disponibiliza os scripts de providers/aws/ em /data/aws-monitor/bin (fonte única
#      de verdade continua em providers/aws/; aqui é só uma cópia estável para o n8n chamar)
#   6) importa o workflow N8N via REST API (se o n8n já estiver instalado/rodando),
#      com fallback para instrução de import manual
#   7) valida
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck disable=SC1091
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/os.sh"
# shellcheck disable=SC1091
source "${SP_ROOT}/core/docker.sh"
# shellcheck disable=SC1091
source "${SP_ROOT}/providers/aws/detect.sh"

SLUG="aws-monitor"
UPDATE=false
[[ "${1:-}" == "--update" ]] && UPDATE=true

ENV_FILE="${SP_ROOT}/modules/${SLUG}/.env"
DATA_DIR="$(sp::ensure_data_dir "$SLUG")"
BIN_DIR="${DATA_DIR}/bin"

if [[ -f "$ENV_FILE" ]] && ! $UPDATE; then
  sp::warn "${SLUG} já parece instalado (.env existente). Use '--update' para reconfigurar."
  exit 0
fi

# --- 1) AWS CLI ---------------------------------------------------------------

sp::aws_monitor::ensure_awscli() {
  if sp::has_cmd aws; then
    sp::ok "AWS CLI já instalado ($(aws --version 2>&1 | head -n1))."
    return 0
  fi
  sp::info "Instalando AWS CLI v2..."
  local tmp; tmp="$(mktemp -d)"
  local arch; arch="$(uname -m)"
  local pkg="awscli-exe-linux-x86_64.zip"
  [[ "$arch" == "aarch64" || "$arch" == "arm64" ]] && pkg="awscli-exe-linux-aarch64.zip"

  curl -fsSL "https://awscli.amazonaws.com/${pkg}" -o "${tmp}/awscliv2.zip"
  sp::has_cmd unzip || { sp::info "Instalando unzip..."; sp::os::install_pkg unzip; }
  unzip -q "${tmp}/awscliv2.zip" -d "$tmp"
  "${tmp}/aws/install" --update
  rm -rf "$tmp"
  sp::ok "AWS CLI instalado ($(aws --version 2>&1 | head -n1))."
}

sp::aws_monitor::ensure_jq() {
  sp::has_cmd jq && { sp::ok "jq já instalado."; return 0; }
  sp::info "Instalando jq..."
  sp::os::install_pkg jq
  sp::ok "jq instalado."
}

# --- 2) Credenciais ------------------------------------------------------------

# Estratégia de credenciais em ordem de preferência: Instance Profile (EC2) > aws configure
# já existente > variáveis de ambiente. Nunca escreve chave de acesso em arquivo.
sp::aws_monitor::check_credentials() {
  if sp::aws::is_ec2; then
    sp::info "Instância EC2 detectada. Verificando IAM Instance Profile..."
    local role
    role="$(sp::aws::meta 'iam/security-credentials/' 2>/dev/null || true)"
    if [[ -n "$role" ]]; then
      sp::ok "Instance Profile anexado (role: ${role}). Credenciais resolvidas automaticamente pelo SDK/CLI."
      return 0
    fi
    sp::warn "Nenhum IAM Instance Profile anexado a esta instância."
    sp::warn "Recomendado: anexe a role usando a política em providers/aws/iam-policy-aws-monitor.json"
    sp::warn "  (nunca use Access Key/Secret Key hardcoded em produção)."
  fi

  if aws sts get-caller-identity >/dev/null 2>&1; then
    sp::ok "Credenciais AWS válidas encontradas (aws configure / variáveis de ambiente)."
    return 0
  fi

  sp::warn "Nenhuma credencial AWS válida encontrada."
  if sp::confirm "Deseja rodar 'aws configure' agora (uso local/dev; prefira Instance Profile em produção)?"; then
    aws configure
  else
    sp::warn "Instalação continuará, mas os scripts de cost-report/security-report falharão até"
    sp::warn "as credenciais serem configuradas (Instance Profile, aws configure, ou variáveis"
    sp::warn "AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY lidas de Secrets Manager/SSM em runtime)."
  fi
}

# --- 3) Env ---------------------------------------------------------------------

sp::aws_monitor::write_env() {
  local region
  region="$(sp::aws::region 2>/dev/null || echo 'us-east-1')"

  if [[ -f "$ENV_FILE" ]]; then
    sp::info ".env existente preservado (use valores atuais). Edite ${ENV_FILE} manualmente se necessário."
    return 0
  fi

  cp "${SP_TEMPLATES_DIR}/env/aws-monitor.env.example" "$ENV_FILE"
  sed -i "s/^AWS_REGION=.*/AWS_REGION=${region}/" "$ENV_FILE"

  local email_to
  email_to="$(sp::ask 'E-mail(s) para receber os reports (separados por vírgula)')"
  sed -i "s/^REPORT_EMAIL_TO=.*/REPORT_EMAIL_TO=${email_to}/" "$ENV_FILE"

  sp::ok "Arquivo de configuração criado em ${ENV_FILE}"
  sp::warn "Revise ${ENV_FILE} e preencha SLACK_WEBHOOK_URL / S3_BACKUP_BUCKET / ROUTE53_ZONE_ID se for usar."
}

# --- 4) Scripts disponíveis para o n8n (Execute Command) -----------------------

sp::aws_monitor::stage_scripts() {
  mkdir -p "$BIN_DIR"
  install -m 750 "${SP_PROVIDERS_DIR}/aws/cost-report.sh" "${BIN_DIR}/cost-report.sh"
  install -m 750 "${SP_PROVIDERS_DIR}/aws/security-report.sh" "${BIN_DIR}/security-report.sh"
  install -m 750 "${SP_PROVIDERS_DIR}/aws/backup-s3.sh" "${BIN_DIR}/backup-s3.sh"
  install -m 750 "${SP_PROVIDERS_DIR}/aws/route53.sh" "${BIN_DIR}/route53.sh"
  install -m 750 "${SP_PROVIDERS_DIR}/aws/cloudwatch.sh" "${BIN_DIR}/cloudwatch.sh"
  sp::ok "Scripts disponibilizados em ${BIN_DIR} (chamados pelo node 'Execute Command' do n8n)."
}

# --- 5) Import do workflow N8N via REST API -------------------------------------

sp::aws_monitor::import_n8n_workflow() {
  local workflow_file="${SP_TEMPLATES_DIR}/n8n-workflows/aws-finops-report.json"
  [[ -f "$workflow_file" ]] || { sp::warn "Workflow template não encontrado: ${workflow_file}"; return 0; }

  if ! sp::is_stack_up n8n; then
    sp::warn "n8n não está instalado/rodando. Pulando import automático do workflow."
    sp::warn "Import manual: abra o n8n -> Workflows -> Import from File -> selecione:"
    sp::warn "  ${workflow_file}"
    return 0
  fi

  # shellcheck disable=SC1090
  set -a; source "${SP_ROOT}/modules/n8n/.env" 2>/dev/null || true; set +a
  local n8n_url="https://${DOMAIN:-localhost:5678}"
  local api_key="${N8N_API_KEY:-}"

  if [[ -z "$api_key" ]]; then
    sp::warn "N8N_API_KEY não configurada. Para import automático via API:"
    sp::warn "  1) No n8n: Settings -> n8n API -> Create an API key"
    sp::warn "  2) Adicione N8N_API_KEY=<chave> em ${SP_ROOT}/modules/n8n/.env"
    sp::warn "  3) Reexecute: modules/aws-monitor/install.sh --update"
    sp::warn "Alternativa manual: Workflows -> Import from File -> ${workflow_file}"
    return 0
  fi

  sp::info "Importando workflow 'AWS FinOps Report' via API do n8n (${n8n_url})..."
  local http_code
  http_code="$(curl -s -o /tmp/n8n-import-response.json -w '%{http_code}' \
    -X POST "${n8n_url}/api/v1/workflows" \
    -H "X-N8N-API-KEY: ${api_key}" \
    -H "Content-Type: application/json" \
    --data-binary "@${workflow_file}" || echo '000')"

  if [[ "$http_code" =~ ^2 ]]; then
    sp::ok "Workflow importado com sucesso no n8n (HTTP ${http_code})."
    sp::warn "Ative o workflow manualmente no n8n e configure as credentials de Email/Slack nos nodes."
  else
    sp::warn "Import automático falhou (HTTP ${http_code}). Veja /tmp/n8n-import-response.json."
    sp::warn "Import manual: Workflows -> Import from File -> ${workflow_file}"
  fi
}

# --- main -------------------------------------------------------------------

sp::aws_monitor::ensure_awscli
sp::aws_monitor::ensure_jq
sp::aws::advise 2>/dev/null || true
sp::aws_monitor::check_credentials
sp::aws_monitor::write_env
sp::aws_monitor::stage_scripts
sp::aws_monitor::import_n8n_workflow

sp::ok "AWS Monitor / FinOps Agent instalado."
sp::info "Teste manual: bash ${BIN_DIR}/cost-report.sh && bash ${BIN_DIR}/security-report.sh"
sp::log "INSTALL" "$SLUG" "data_dir=${DATA_DIR} bin_dir=${BIN_DIR}"
