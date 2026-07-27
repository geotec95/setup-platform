#!/bin/bash
# core/proxy.sh — reverse proxy (Traefik) + SSL + resolução de domínio/IP
set -Eeuo pipefail

# Garante que existe stack do Traefik rodando; se não, propõe instalar.
sp::proxy::ensure_traefik() {
  if sp::is_stack_up traefik; then
    sp::ok "Traefik já está rodando."
    return 0
  fi
  sp::warn "Traefik não está instalado. Ferramentas com painel web precisam de proxy reverso + HTTPS."
  sp::confirm "Instalar Traefik agora?" && sp::proxy::install_traefik
}

sp::proxy::install_traefik() {
  local email
  email="$(sp::ask "E-mail para certificados Let's Encrypt (ACME)")"

  mkdir -p "${SP_ROOT}/config/traefik"
  sed "s/{{EMAIL}}/${email}/g" "${SP_TEMPLATES_DIR}/traefik/traefik.yml.tpl" \
    > "${SP_ROOT}/config/traefik/traefik.yml"

  sp::docker::init_swarm "$(sp::aws::private_ip 2>/dev/null || true)"
  sp::docker::ensure_network rede_publica
  docker volume inspect traefik_certificates >/dev/null 2>&1 || docker volume create traefik_certificates
  sp::docker::deploy_stack traefik "${SP_TEMPLATES_DIR}/traefik/docker-compose.yml"
  sp::ok "Traefik instalado. HTTPS automático via Let's Encrypt habilitado."
}

# Pede subdomínio, valida formato básico e confirma resolução DNS antes de seguir.
# Uso: dominio="$(sp::proxy::ask_domain n8n)"
sp::proxy::ask_domain() {
  local tool="$1" domain resolved_ip target_ip
  domain="$(sp::ask "Subdomínio para ${tool} (ex: ${tool}.seudominio.com)")"

  if ! [[ "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
    sp::err "Domínio inválido: ${domain}"
    return 1
  fi

  target_ip="$(sp::network::public_ip || true)"
  resolved_ip="$(dig +short "$domain" A | tail -n1)"

  if [[ -n "$target_ip" && "$resolved_ip" != "$target_ip" ]]; then
    sp::warn "DNS de ${domain} aponta para '${resolved_ip:-<vazio>}', mas o IP público do servidor é '${target_ip}'."
    sp::warn "Configure um registro A em ${domain} -> ${target_ip} (ou CNAME, se usar Cloudflare proxy) antes de continuar."
    sp::confirm "Continuar mesmo assim (o certificado SSL pode falhar)?" || return 1
  else
    sp::ok "DNS de ${domain} resolvendo corretamente para ${target_ip}."
  fi

  echo "$domain"
}
