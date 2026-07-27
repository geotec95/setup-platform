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
    amzn-2|amzn-2023|rhel-8|rhel-9|rocky-8|rocky-9|almalinux-8|almalinux-9|centos-8|centos-9)
      sp::ok "SO suportado (família RHEL): ${PRETTY_NAME}"
      ;;
    *)
      sp::warn "SO não homologado: ${PRETTY_NAME:-desconhecido}. Prosseguindo por sua conta e risco."
      sp::confirm "Continuar mesmo assim?" || exit 1
      ;;
  esac
}

# Detecta o gerenciador de pacotes desta distro. Usado por install_base_deps
# e setup_firewall pra saber qual caminho seguir (Debian/Ubuntu vs RHEL/Amazon Linux).
sp::os::pkg_manager() {
  if sp::has_cmd apt-get; then
    echo apt
  elif sp::has_cmd dnf; then
    echo dnf
  elif sp::has_cmd yum; then
    echo yum
  else
    echo unknown
  fi
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

# Instala uma lista de pacotes usando o gerenciador certo pra esta distro.
# Uso: sp::os::install_pkg unzip jq ...  (nomes de pacote iguais em apt/dnf/yum;
# para nomes que divergem entre distros, resolva antes de chamar esta função).
sp::os::install_pkg() {
  case "$(sp::os::pkg_manager)" in
    apt) apt-get update -qq && apt-get install -y -qq "$@" ;;
    dnf) dnf install -y -q "$@" ;;
    yum) yum install -y -q "$@" ;;
    *) sp::err "Gerenciador de pacotes não reconhecido, instale manualmente: $*"; return 1 ;;
  esac
}

sp::os::install_base_deps() {
  sp::info "Atualizando pacotes e instalando dependências base..."
  case "$(sp::os::pkg_manager)" in
    apt)
      sp::run os apt-get update -y
      sp::run os apt-get upgrade -y
      sp::run os apt-get install -y curl wget git jq apt-utils dialog apache2-utils ca-certificates gnupg lsb-release ufw
      ;;
    dnf)
      sp::run os dnf install -y curl wget git jq dialog httpd-tools ca-certificates gnupg2 firewalld
      ;;
    yum)
      sp::run os yum install -y curl wget git jq dialog httpd-tools ca-certificates gnupg2 firewalld
      ;;
    *)
      sp::err "Gerenciador de pacotes não reconhecido (nem apt-get, nem dnf, nem yum). Instale manualmente: curl wget git jq."
      exit 1
      ;;
  esac
  sp::ok "Dependências base instaladas."
}

# Firewall básico: nega tudo de entrada, libera SSH/HTTP/HTTPS. Módulos abrem
# portas extras explicitamente. Usa ufw (Debian/Ubuntu) ou firewalld (RHEL/Amazon
# Linux), conforme o que estiver disponível.
sp::os::setup_firewall() {
  if sp::has_cmd ufw; then
    ufw default deny incoming >/dev/null
    ufw default allow outgoing >/dev/null
    ufw allow OpenSSH >/dev/null
    ufw allow 80/tcp >/dev/null
    ufw allow 443/tcp >/dev/null
    ufw --force enable >/dev/null
    sp::ok "UFW ativo (deny incoming por padrão, libera 22/80/443)."
  elif sp::has_cmd firewall-cmd; then
    systemctl enable --now firewalld >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-service=ssh >/dev/null
    firewall-cmd --permanent --add-service=http >/dev/null
    firewall-cmd --permanent --add-service=https >/dev/null
    firewall-cmd --reload >/dev/null
    sp::ok "firewalld ativo (zona padrão nega entrada por padrão, libera ssh/http/https)."
  else
    sp::warn "Nenhum firewall local (ufw/firewalld) encontrado — dependendo 100% do Security Group da AWS."
  fi
}
