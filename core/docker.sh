#!/bin/bash
# core/docker.sh — instalação e helpers Docker/Swarm/Compose
set -Eeuo pipefail

sp::docker::install() {
  if sp::has_cmd docker; then
    sp::ok "Docker já instalado ($(docker --version))."
  else
    sp::info "Instalando Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker >/dev/null 2>&1
    systemctl start docker
    sp::ok "Docker instalado."
  fi

  if ! docker compose version >/dev/null 2>&1; then
    sp::err "Docker Compose plugin ausente. Reinstale via get.docker.com."
    exit 1
  fi
}

# Inicializa Swarm se ainda não estiver ativo (necessário para Traefik + secrets + overlay network)
sp::docker::init_swarm() {
  if docker info 2>/dev/null | grep -q "Swarm: active"; then
    sp::ok "Docker Swarm já ativo."
    return 0
  fi
  local advertise_ip="${1:-}"
  if [[ -n "$advertise_ip" ]]; then
    docker swarm init --advertise-addr "$advertise_ip"
  else
    docker swarm init
  fi
  sp::ok "Docker Swarm inicializado."
}

sp::docker::ensure_network() {
  local net="${1:-rede_publica}"
  if ! docker network inspect "$net" >/dev/null 2>&1; then
    docker network create --driver=overlay --attachable "$net"
    sp::ok "Rede overlay '${net}' criada."
  fi
}

# Deploy idempotente de uma stack compose. Uso: sp::docker::deploy_stack <nome> <arquivo-compose>
sp::docker::deploy_stack() {
  local name="$1" compose_file="$2"
  docker stack deploy -c "$compose_file" --detach=true "$name"
  sp::ok "Stack '${name}' deployada a partir de ${compose_file}."
}

sp::docker::remove_stack() {
  local name="$1"
  if docker stack ls --format '{{.Name}}' | grep -qx "$name"; then
    docker stack rm "$name"
    sp::ok "Stack '${name}' removida."
  else
    sp::warn "Stack '${name}' não encontrada."
  fi
}

sp::docker::stack_status() {
  local name="$1"
  docker stack services "$name" 2>/dev/null
}
