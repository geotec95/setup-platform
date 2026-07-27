#!/bin/bash
# providers/aws/backup-s3.sh — helper genérico de backup em S3, reutilizável por
# QUALQUER módulo do setup-platform (n8n, bancos de dados, dashboards, etc.).
#
# Uso:
#   source providers/aws/backup-s3.sh
#   sp::aws::s3_backup <caminho_local> <bucket> <prefixo> [retencao=30]
#
# Comportamento:
#   - Envia <caminho_local> (arquivo ou diretório) para s3://<bucket>/<prefixo>/<timestamp>/
#   - Usa SSE-S3 (AES256) por padrão — criptografia em repouso sem gerenciar chaves.
#   - Rotaciona: mantém apenas os N backups mais recentes sob o prefixo (remove os antigos).
#   - Idempotente: reexecutar não duplica o backup do mesmo timestamp (chave inclui data/hora).
set -Eeuo pipefail

SP_ROOT="${SP_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
# shellcheck disable=SC1091
source "${SP_ROOT}/core/common.sh"

sp::aws::_s3_check_prereqs() {
  sp::has_cmd aws || { sp::err "AWS CLI não encontrado."; return 1; }
  return 0
}

# sp::aws::s3_backup <caminho_local> <bucket> <prefixo> [retencao]
sp::aws::s3_backup() {
  local local_path="$1" bucket="$2" prefix="$3" retention="${4:-30}"

  sp::aws::_s3_check_prereqs || return 1
  [[ -e "$local_path" ]] || { sp::err "Caminho local não existe: ${local_path}"; return 1; }
  [[ -n "$bucket" ]] || { sp::err "Bucket S3 não informado (S3_BACKUP_BUCKET)."; return 1; }

  local stamp dest
  stamp="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
  dest="s3://${bucket}/${prefix%/}/${stamp}"

  sp::info "Enviando backup de ${local_path} para ${dest} (SSE-S3)..."
  if [[ -d "$local_path" ]]; then
    aws s3 sync "$local_path" "$dest" --sse AES256 --only-show-errors
  else
    aws s3 cp "$local_path" "${dest}/$(basename "$local_path")" --sse AES256 --only-show-errors
  fi
  sp::ok "Backup enviado: ${dest}"

  sp::aws::_s3_rotate "$bucket" "$prefix" "$retention"
}

# Remove backups mais antigos que os N mais recentes sob s3://<bucket>/<prefixo>/
sp::aws::_s3_rotate() {
  local bucket="$1" prefix="$2" retention="$3"

  local dirs
  dirs="$(aws s3 ls "s3://${bucket}/${prefix%/}/" | awk '{print $2}' | sed 's#/$##' | sort)"
  local total; total="$(echo "$dirs" | grep -c . || true)"

  if [[ "$total" -le "$retention" ]]; then
    sp::log "INFO" "aws-s3-backup" "Rotação: ${total}/${retention} backups, nada a remover."
    return 0
  fi

  local to_remove; to_remove="$((total - retention))"
  local old_dirs; old_dirs="$(echo "$dirs" | head -n "$to_remove")"

  local d
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    sp::info "Rotação S3: removendo backup antigo ${d}"
    aws s3 rm "s3://${bucket}/${prefix%/}/${d}/" --recursive --only-show-errors
  done <<< "$old_dirs"

  sp::ok "Rotação concluída: mantidos os ${retention} backups mais recentes."
}
