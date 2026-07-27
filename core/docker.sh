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
  # Sem --detach: a flag não existe em builds mais antigos do Docker CLI
  # (ex: pacote "docker" do Amazon Linux 2/2023, que reporta versão recente
  # mas empacota um CLI mais velho). Todo Docker moderno já trata stack
  # deploy como não-interativo por padrão, então omitir a flag é seguro.
  docker stack deploy -c "$compose_file" "$name"
  sp::ok "Stack '${name}' deployada a partir de ${compose_file}."
}

# Força a recriação de serviços cujo ÚNICO ponto de configuração é um bind
# mount de arquivo (ex: prometheus.yml, promtail-config.yml). O Swarm só
# recria um container quando a SPEC do serviço muda (imagem, labels, env,
# etc) — mudar apenas o CONTEÚDO de um arquivo montado via bind não é
# detectado, e o container antigo continua rodando com a config velha
# indefinidamente. Uso: sp::docker::force_restart <serviço1> [serviço2 ...]
sp::docker::force_restart() {
  local svc
  for svc in "$@"; do
    docker service update --force "$svc" >/dev/null
  done
  sp::ok "Serviços recriados (config de arquivo recarregada): $*"
}

# Tenta identificar linguagem/framework de um container e sugere a
# biblioteca de métricas Prometheus correspondente — usado por
# modules/remote-agent/install.sh pra poupar o operador de ter que
# descobrir isso na mão a cada cliente novo (ver caso real: precisou de
# 3 rodadas de investigação manual pro wri-bioeconomy-backend, que era
# Django). É heurística — sempre um "achado provável", nunca certeza
# absoluta; o operador confirma/ajusta manualmente se a sugestão não bater.
# Uso: sp::docker::detect_app_stack <container>
sp::docker::detect_app_stack() {
  local container="$1"
  local proc_args files_hint=""

  if ! docker inspect "$container" >/dev/null 2>&1; then
    sp::warn "Container '${container}' não encontrado — pulando detecção automática."
    return 0
  fi

  # `docker top` lê a tabela de processos do host — funciona mesmo se o
  # container não tiver shell/ferramentas instaladas.
  proc_args="$(docker top "$container" -eo args 2>/dev/null | tail -n +2)"

  # Reforço best-effort: arquivos de manifesto na raiz comum de apps
  # (só funciona se o container tiver /bin/sh; ignora erro se não tiver).
  files_hint="$(docker exec "$container" sh -c \
    'for f in manage.py package.json requirements.txt Gemfile go.mod pom.xml build.gradle composer.json; do [ -f "/app/$f" ] && echo "$f"; [ -f "/$f" ] && echo "$f"; done' \
    2>/dev/null | sort -u | tr '\n' ' ')"

  local lang="" framework="" pkg=""
  case "$proc_args" in
    *gunicorn*|*uwsgi*)
      lang="Python (WSGI)"
      if [[ "$files_hint" == *manage.py* ]] || echo "$proc_args" | grep -qi "wsgi:application\|/wsgi\b"; then
        framework="Django"; pkg="django-prometheus"
      else
        framework="Flask (ou outro WSGI)"; pkg="prometheus-flask-exporter"
      fi
      ;;
    *uvicorn*|*daphne*|*hypercorn*)
      lang="Python (ASGI)"
      framework="FastAPI (ou outro ASGI)"; pkg="prometheus-fastapi-instrumentator"
      ;;
    *"manage.py runserver"*|*"manage.py"*)
      lang="Python"; framework="Django"; pkg="django-prometheus"
      ;;
    *node*)
      lang="Node.js"; framework="Express/Fastify/Koa (genérico)"; pkg="prom-client"
      ;;
    *"java "*)
      lang="Java"
      if echo "$proc_args$files_hint" | grep -qi "spring"; then
        framework="Spring Boot"; pkg="micrometer-registry-prometheus"
      else
        framework="JVM genérico"; pkg="simpleclient (io.prometheus:simpleclient)"
      fi
      ;;
    *puma*|*unicorn*|*ruby*)
      lang="Ruby"; framework="Rails (provável)"; pkg="yabeda-prometheus"
      ;;
    *php-fpm*|*php*)
      lang="PHP"; framework="genérico"; pkg="promphp/prometheus_client_php"
      ;;
    *dotnet*)
      lang=".NET"; framework="ASP.NET Core (provável)"; pkg="prometheus-net.AspNetCore"
      ;;
    *)
      lang="não identificado"
      ;;
  esac

  if [[ -n "$lang" && "$lang" != "não identificado" ]]; then
    sp::ok "Stack detectada em '${container}': ${lang}${framework:+ / ${framework}}."
    [[ -n "$pkg" ]] && sp::info "Sugestão de instrumentação: ${pkg} (expõe /metrics no formato Prometheus)."
  else
    sp::warn "Não consegui identificar a stack de '${container}' automaticamente (processo: ${proc_args:-desconhecido}). Configure a instrumentação manualmente."
  fi
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
