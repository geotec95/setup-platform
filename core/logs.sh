#!/bin/bash
# core/logs.sh — visualização de logs do sistema e das stacks
set -Eeuo pipefail

sp::logs::tail_platform() {
  local n="${1:-100}"
  tail -n "$n" -f "${SP_LOG_DIR}/setup-platform.log"
}

sp::logs::tail_tool() {
  local slug="$1" lines="${2:-200}"
  docker service logs --tail "$lines" -f "${slug}_${slug}" 2>/dev/null \
    || docker logs --tail "$lines" -f "$slug" 2>/dev/null \
    || sp::err "Nenhum serviço/container encontrado para '${slug}'."
}
