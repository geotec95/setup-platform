#!/bin/bash
# core/validate.sh — validação de manifests e checagem pós-instalação
set -Eeuo pipefail

# Valida se um manifesto YAML tem os campos obrigatórios
sp::validate::manifest() {
  local file="$1"
  local required=(name slug category description install_strategy validate_command uninstall_strategy)
  local missing=()

  for field in "${required[@]}"; do
    local val
    val="$(yq eval ".${field}" "$file" 2>/dev/null)"
    [[ -z "$val" || "$val" == "null" ]] && missing+=("$field")
  done

  if (( ${#missing[@]} > 0 )); then
    sp::err "Manifesto ${file} inválido. Campos ausentes: ${missing[*]}"
    return 1
  fi
  return 0
}

# Roda o validate_command definido no manifesto e reporta status
sp::validate::tool() {
  local slug="$1"
  local manifest="${SP_CONFIG_DIR}/tools/${slug}.yaml"
  [[ -f "$manifest" ]] || { sp::err "Manifesto não encontrado: ${manifest}"; return 1; }

  local cmd
  cmd="$(sp::yaml_get "$manifest" '.validate_command')"
  sp::info "Validando ${slug}: ${cmd}"
  if eval "$cmd" >/dev/null 2>&1; then
    sp::ok "${slug} está saudável."
    return 0
  else
    sp::err "${slug} falhou na validação."
    return 1
  fi
}

# Valida todas as ferramentas instaladas (usadas no menu de Diagnóstico)
sp::validate::all() {
  local f slug
  for f in "${SP_CONFIG_DIR}"/tools/*.yaml; do
    [[ -e "$f" ]] || continue
    slug="$(sp::yaml_get "$f" '.slug')"
    sp::is_stack_up "$slug" && sp::validate::tool "$slug"
  done
}
