#!/bin/bash
# core/common.sh — funções utilitárias compartilhadas por todo o setup-platform
set -Eeuo pipefail

# Diretórios base (relativos à raiz do projeto)
SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SP_LOG_DIR="${SP_ROOT}/logs"
SP_BACKUP_DIR="${SP_ROOT}/backups"
SP_CONFIG_DIR="${SP_ROOT}/config"
SP_MODULES_DIR="${SP_ROOT}/modules"
SP_TEMPLATES_DIR="${SP_ROOT}/templates"
SP_PROVIDERS_DIR="${SP_ROOT}/providers"
SP_DATA_ROOT="/data"

# Cores
readonly C_RESET="\e[0m"
readonly C_BOLD="\e[1m"
readonly C_DIM="\e[2m"
readonly C_GREEN="\e[32m"
readonly C_YELLOW="\e[33m"
readonly C_RED="\e[91m"
readonly C_BLUE="\e[94m"
readonly C_WHITE="\e[97m"
readonly C_CYAN="\e[96m"
readonly C_MAGENTA="\e[95m"

sp::ok()    { echo -e "${C_GREEN}[OK]${C_RESET} $*" >&2; }
sp::warn()  { echo -e "${C_YELLOW}[WARN]${C_RESET} $*" >&2; }
sp::err()   { echo -e "${C_RED}[ERRO]${C_RESET} $*" >&2; }
sp::info()  { echo -e "${C_BLUE}[INFO]${C_RESET} $*" >&2; }

# Log estruturado: sp::log <nivel> <modulo> <mensagem>
sp::log() {
  local level="$1"; local module="$2"; shift 2
  local ts
  ts="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
  mkdir -p "$SP_LOG_DIR"
  printf '%s [%s] [%s] %s\n' "$ts" "$level" "$module" "$*" >> "${SP_LOG_DIR}/setup-platform.log"
}

# Executa comando com log + tratamento de erro sem matar o shell interativo do menu
sp::run() {
  local module="$1"; shift
  sp::log "RUN" "$module" "$*"
  if "$@" >> "${SP_LOG_DIR}/setup-platform.log" 2>&1; then
    sp::log "OK" "$module" "$*"
    return 0
  else
    local rc=$?
    sp::log "FAIL" "$module" "$* (exit=$rc)"
    return "$rc"
  fi
}

# Gera senha segura (32 chars, alfanumérico) — evita caracteres problemáticos em .env/URLs
# Roda em subshell com pipefail desligado: "head -c" fecha o pipe antes do "tr"
# terminar de escrever, o que gera SIGPIPE (exit 141) e, com pipefail ligado,
# derruba o script inteiro sob set -e (às vezes só no comando seguinte).
sp::gen_password() {
  local len="${1:-32}"
  ( set +o pipefail; tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$len" )
}

# Confirmação padrão sim/não. Uso: sp::confirm "Pergunta?" && faz_algo
sp::confirm() {
  local prompt="$1" answer
  read -r -p "$(echo -e "${C_YELLOW}${prompt} [s/N]: ${C_RESET}")" answer
  [[ "$answer" =~ ^([sS][iI]?[mM]?|[yY])$ ]]
}

# Lê input obrigatório
sp::ask() {
  local prompt="$1" var
  while true; do
    read -r -p "$(echo -e "${C_WHITE}${prompt}: ${C_RESET}")" var
    [[ -n "$var" ]] && { echo "$var"; return 0; }
    sp::warn "Valor obrigatório."
  done
}

# Verifica se um comando existe no PATH
sp::has_cmd() { command -v "$1" >/dev/null 2>&1; }

# Idempotência: verifica se um container/stack já está rodando (usado pelos módulos)
sp::is_stack_up() {
  local stack_name="$1"
  docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${stack_name}" \
    || docker stack ls --format '{{.Name}}' 2>/dev/null | grep -qx "$stack_name"
}

# Cria diretório de dados padrão /data/<tool> com permissões restritas
sp::ensure_data_dir() {
  local tool="$1"
  local dir="${SP_DATA_ROOT}/${tool}"
  mkdir -p "$dir"
  chmod 750 "$dir"
  echo "$dir"
}

# Carrega valor de um manifesto YAML (requer yq). Uso: sp::yaml_get file.yaml '.campo'
sp::yaml_get() {
  local file="$1" query="$2"
  if ! sp::has_cmd yq; then
    sp::err "yq não instalado. Rode a instalação base do servidor primeiro."
    return 1
  fi
  yq eval "$query" "$file"
}
