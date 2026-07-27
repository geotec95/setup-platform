#!/bin/bash
# bin/bootstrap.sh — script que fica hospedado no seu endpoint (ex: setup.arcuscloud.com.br)
# É o único arquivo que o `bash -c "$(curl -sSL ...)"` precisa baixar. Ele clona/atualiza
# o repo completo e chama bin/setup.sh. Mantém o comando único de instalação, igual ao
# fluxo do SetupOrion, mas com a base própria e o fix de IP da AWS já embutido.
#
# Use `bash -c "$(curl -sSL ...)"` (command substitution), NÃO `bash <(curl -sSL ...)`
# (process substitution) — a segunda forma depende de /dev/fd, ausente em algumas
# distribuições (Amazon Linux, RHEL); a primeira funciona em qualquer shell POSIX.
set -Eeuo pipefail

REPO_URL="${SP_REPO_URL:-https://github.com/geotec95/setup-platform.git}"
INSTALL_DIR="/opt/setup-platform"

if [[ "$(id -u)" -ne 0 ]]; then
  echo 'Rode como root: sudo bash -c "$(curl -sSL setup.arcuscloud.com.br)"'
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y git
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y git
  elif command -v yum >/dev/null 2>&1; then
    yum install -y git
  else
    echo "Não achei apt-get/dnf/yum pra instalar o git. Instale manualmente e rode de novo." >&2
    exit 1
  fi
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" pull --ff-only
else
  git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR"/bin/*.sh "$INSTALL_DIR"/core/*.sh "$INSTALL_DIR"/providers/aws/*.sh \
  "$INSTALL_DIR"/modules/*/*.sh 2>/dev/null || true

exec bash "$INSTALL_DIR/bin/setup.sh"
