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

# Auto-atualiza o setup-platform ANTES de sourcear o resto do núcleo — assim
# qualquer correção de bug já entra em vigor nesta mesma execução. Só faz
# fast-forward (nunca sobrescreve mudança local); se divergir ou não tiver
# rede, avisa e segue com a versão que já está no disco.
if [[ -d "${SP_ROOT}/.git" ]] && sp::has_cmd git; then
  sp::info "Verificando atualizações do setup-platform..."
  CURRENT_COMMIT="$(git -C "$SP_ROOT" rev-parse --short HEAD 2>/dev/null || echo "?")"
  if git -C "$SP_ROOT" fetch --quiet origin 2>/dev/null; then
    if git -C "$SP_ROOT" pull --ff-only --quiet 2>/dev/null; then
      NEW_COMMIT="$(git -C "$SP_ROOT" rev-parse --short HEAD 2>/dev/null || echo "?")"
      if [[ "$CURRENT_COMMIT" != "$NEW_COMMIT" ]]; then
        sp::ok "setup-platform atualizado (${CURRENT_COMMIT} -> ${NEW_COMMIT}). Reiniciando com a versão nova..."
        exec bash "${BASH_SOURCE[0]}" "$@"
      else
        sp::ok "setup-platform já está na última versão (${CURRENT_COMMIT})."
      fi
    else
      sp::warn "Não consegui atualizar automaticamente (mudanças locais ou histórico divergente). Rode 'git pull' manualmente em ${SP_ROOT} se precisar da versão mais nova."
    fi
  else
    sp::warn "Sem rede pra checar atualizações — seguindo com a versão local."
  fi
fi

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
