#!/bin/bash
set -Eeuo pipefail
SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"

sp::confirm "Remover a stack remote-agent? Os dados em /data/remote-agent serão preservados." && \
  sp::docker::remove_stack remote-agent
