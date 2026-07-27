#!/bin/bash
# core/os.sh — validação de sistema operacional e requisitos mínimos
set -Eeuo pipefail

sp::os::check_supported() {
  if [[ ! -f /etc/os-release ]]; then
    sp::err "Não foi possível identificar o SO (/etc/os-release ausente)."
    exit 1
  fi
  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID}-${VERSION_ID}" in
    ubuntu-20.04|ubuntu-22.04|ubuntu-24.04|debian-11|debian-12)
      sp::ok "SO suportado: ${PRETTY_NAME}"
      ;;
    *)
      sp::warn "SO não homologado: ${PRETTY_NAME:-desconhecido}. Prosseguindo por sua conta e risco."
      sp::confirm "Continuar mesmo assim?" || exit 1
      ;;
  esac
}

sp::os::check_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    sp::err "Este script precisa ser executado como root (sudo -i ou sudo bash bin/setup.sh)."
    exit 1
  fi
}

sp::os::check_resources() {
  local min_ram_mb="${1:-2048}"
  local min_vcpu="${2:-1}"
  local ram_mb vcpu
  ram_mb=$(free -m | awk '/^Mem:/{print $2}')
  vcpu=$(nproc)

  if (( ram_mb < min_ram_mb )); then
    sp::warn "RAM detectada: ${ram_mb}MB (mínimo recomendado: ${min_ram_mb}MB)"
  else
    sp::ok "RAM: ${ram_mb}MB"
  fi

  if (( vcpu < min_vcpu )); then
    sp::warn "vCPUs detectadas: ${vcpu} (mínimo recomendado: ${min_vcpu})"
  else
    sp::ok "vCPUs: ${vcpu}"
  fi
}

sp::os::install_base_deps() {
  sp::info "Atualizando pacotes e instalando dependências base..."
  sp::run os apt-get update -y
  sp::run os apt-get upgrade -y
  sp::run os apt-get install -y curl wget git jq apt-utils dialog apache2-utils ca-certificates gnupg lsb-release ufw
  sp::ok "Dependências base instaladas."
}

# UFW básico: nega tudo de entrada, libera SSH/HTTP/HTTPS. Módulos abrem portas extras explicitamente.
sp::os::setup_firewall() {
  if ! sp::has_cmd ufw; then
    sp::warn "ufw não encontrado, pulando configuração de firewall."
    return 0
  fi
  ufw default deny incoming >/dev/null
  ufw default allow outgoing >/dev/null
  ufw allow OpenSSH >/dev/null
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
  ufw --force enable >/dev/null
  sp::ok "UFW ativo (deny incoming por padrão, libera 22/80/443)."
}
