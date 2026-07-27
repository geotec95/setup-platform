#!/bin/bash
# providers/aws/detect.sh — detecção de ambiente AWS e resolução correta de IP público
#
# PROBLEMA QUE ESTE ARQUIVO RESOLVE:
# Instaladores genéricos (ex: SetupOrion) descobrem o IP via `hostname -I` / `ip addr`,
# o que numa EC2 retorna o IP PRIVADO da ENI (10.x/172.x), pois o IP público é NAT 1:1
# feito pela AWS fora da interface de rede. Este módulo usa o IMDSv2 (metadata service)
# para resolver o IP público real e outros metadados da instância.
set -Eeuo pipefail

readonly IMDS_BASE="http://169.254.169.254/latest"
readonly IMDS_TIMEOUT=2

sp::aws::is_ec2() {
  # Detecção rápida e sem custo: tenta obter token IMDSv2. Se falhar, não é EC2 (ou IMDS bloqueado).
  local token
  token=$(curl -s -m "$IMDS_TIMEOUT" -X PUT "${IMDS_BASE}/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null) || return 1
  [[ -n "$token" ]]
}

sp::aws::imds_token() {
  curl -s -m "$IMDS_TIMEOUT" -X PUT "${IMDS_BASE}/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 21600"
}

sp::aws::meta() {
  local path="$1" token
  token=$(sp::aws::imds_token)
  curl -s -m "$IMDS_TIMEOUT" -H "X-aws-ec2-metadata-token: ${token}" "${IMDS_BASE}/meta-data/${path}"
}

# IP público real da instância (via metadata). Vazio se instância não tiver IP público/EIP associado.
sp::aws::public_ip() {
  sp::aws::meta "public-ipv4"
}

sp::aws::private_ip() {
  sp::aws::meta "local-ipv4"
}

sp::aws::instance_id() {
  sp::aws::meta "instance-id"
}

sp::aws::az() {
  sp::aws::meta "placement/availability-zone"
}

sp::aws::region() {
  sp::aws::az | sed 's/[a-z]$//'
}

# Função central usada pelo core/menu.sh e pelos módulos para descobrir o IP a anunciar
# no Traefik/DNS. Resolve corretamente em EC2 (público via IMDS) e em VPS genérica
# (fallback para serviço externo de IP público).
sp::network::public_ip() {
  if sp::aws::is_ec2; then
    local ip
    ip="$(sp::aws::public_ip)"
    if [[ -z "$ip" ]]; then
      sp::warn "Instância EC2 sem IP público/Elastic IP associado."
      sp::warn "Associe um Elastic IP (recomendado, evita IP mudar em stop/start) ou use um Load Balancer/Cloudflare Tunnel."
      return 1
    fi
    sp::log "INFO" "aws" "IP público resolvido via IMDSv2: ${ip}"
    echo "$ip"
    return 0
  fi

  # Fora da AWS: fallback para serviço externo (comportamento tipo SetupOrion)
  curl -s -m 5 https://ifconfig.me || curl -s -m 5 https://api.ipify.org
}

# Aviso de custo/segurança proativo — chamado no fluxo de instalação em EC2
sp::aws::advise() {
  sp::info "Ambiente AWS detectado (instância: $(sp::aws::instance_id 2>/dev/null || echo '?'), região: $(sp::aws::region 2>/dev/null || echo '?'))"
  local ip
  ip="$(sp::aws::public_ip 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    sp::warn "Sem Elastic IP: o IP público muda a cada stop/start, quebrando DNS/Traefik. Considere alocar um EIP."
  fi
  sp::warn "Segurança: confira o Security Group — só 22 (idealmente via SSM, não 0.0.0.0/0), 80 e 443 devem estar públicos."
  sp::warn "Custo: EIP não associado a instância em execução gera cobrança (~US$0,005/h). Libere IPs não usados."
}
