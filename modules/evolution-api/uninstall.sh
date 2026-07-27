#!/bin/bash
set -Eeuo pipefail
SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"

sp::confirm "Remover a stack evolution-api? Os dados (instâncias/sessão WhatsApp) em /data/evolution-api serão preservados." && \
  sp::docker::remove_stack evolution-api
