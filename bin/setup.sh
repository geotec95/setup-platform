#!/bin/bash
# bin/setup.sh — entrypoint único do setup-platform
#
# Uso local:
#   sudo bash bin/setup.sh
#
# Uso remoto (bootstrap, estilo "um comando só"):
#   bash <(curl -sSL https://setup.SEUDOMINIO.com.br)
#   (esse endpoint deve apenas fazer git clone/curl deste repo e chamar este arquivo)
set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=core/common.sh
source "${SP_ROOT}/core/common.sh"
# shellcheck source=core/os.sh
source "${SP_ROOT}/core/os.sh"
# shellcheck source=core/docker.sh
source "${SP_ROOT}/core/docker.sh"
# shellcheck source=core/proxy.sh
source "${SP_ROOT}/core/proxy.sh"
# shellcheck source=core/logs.sh
source "${SP_ROOT}/core/logs.sh"
# shellcheck source=core/validate.sh
source "${SP_ROOT}/core/validate.sh"
# shellcheck source=providers/aws/detect.sh
source "${SP_ROOT}/providers/aws/detect.sh"
# shellcheck source=core/menu.sh
source "${SP_ROOT}/core/menu.sh"

mkdir -p "$SP_LOG_DIR" "$SP_BACKUP_DIR"

sp::os::check_root
sp::os::check_supported
sp::os::check_resources 2048 2

if sp::aws::is_ec2; then
  sp::aws::advise
fi

if ! sp::has_cmd yq; then
  sp::info "Instalando yq (parser YAML usado pelos manifests)..."
  ARCH="$(dpkg --print-architecture 2>/dev/null || echo amd64)"
  curl -sSL "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${ARCH}" -o /usr/local/bin/yq
  chmod +x /usr/local/bin/yq
fi

sp::docker::install

sp::menu::main
