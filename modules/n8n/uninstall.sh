#!/bin/bash
set -Eeuo pipefail
SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"

sp::confirm "Remover a stack n8n? Os dados em /data/n8n serão preservados." && \
  sp::docker::remove_stack n8n
