# templates/observability/prometheus.yml.tpl
# Configuração do Prometheus do módulo observability. Copiada para
# /data/observability/config/prometheus/prometheus.yml pelo install.sh, que
# substitui o único placeholder existente ({{UPTIME_KUMA_METRICS_KEY}}) --
# todos os outros alvos usam nomes de serviço do Swarm, resolvidos via DNS
# interno da rede 'rede_publica', sem necessidade de substituição.
global:
  scrape_interval: 15s
  evaluation_interval: 15s

# Regras de gravação: normalizam métricas RED de frameworks diferentes
# (Django, FastAPI, ...) pra um nome único de métrica que os dashboards de
# cliente consultam sem saber qual framework está por trás (ver
# prometheus-recording-rules.yml).
rule_files:
  - /etc/prometheus/rules/app-red.yml

scrape_configs:
  # Métricas do próprio Prometheus
  - job_name: prometheus
    static_configs:
      - targets: ["localhost:9090"]

  # Métricas de containers (CPU, memória, rede, disco por container) via cAdvisor
  - job_name: cadvisor
    static_configs:
      - targets: ["cadvisor:8080"]

  # Métricas do host (CPU, memória, disco, load, etc) via node-exporter
  - job_name: node-exporter
    static_configs:
      - targets: ["node-exporter:9100"]

  # Disponibilidade de frontend/backend de cliente monitorada pelo Uptime
  # Kuma (módulo separado, mesma rede) -- exposta em /metrics protegida por
  # Basic Auth (usuário vazio, senha = API Key gerada em Settings > API Keys
  # no próprio Uptime Kuma). Sem a chave configurada, este job só gera
  # warnings de 401 no log do Prometheus -- não quebra o resto do scrape.
  - job_name: uptime-kuma
    metrics_path: /metrics
    static_configs:
      - targets: ["uptime-kuma:3001"]
    basic_auth:
      username: ""
      password: "{{UPTIME_KUMA_METRICS_KEY}}"

  # -------------------------------------------------------------------------
  # EXTENSÃO FUTURA — auto-discovery via Docker Swarm:
  # Em vez de listar alvos manualmente, é possível habilitar o discovery
  # nativo do Prometheus para Docker (docker_sd_configs) e fazer com que
  # QUALQUER módulo novo do setup-platform (aws-monitor, apps de cliente,
  # futuros serviços) seja monitorado automaticamente, bastando o serviço
  # expor a label `prometheus.io.scrape=true` (e opcionalmente
  # `prometheus.io.port` / `prometheus.io.path`) no seu docker-compose/stack.
  # Isso evita ter que editar este arquivo manualmente a cada novo módulo.
  #
  # Exemplo (requer montar /var/run/docker.sock:ro no serviço prometheus em
  # templates/compose/observability.yml — avaliar impacto de segurança antes
  # de expor o socket Docker ao Prometheus):
  #
  # - job_name: docker-sd
  #   docker_sd_configs:
  #     - host: unix:///var/run/docker.sock
  #       filters:
  #         - name: label
  #           values: ["prometheus.io.scrape=true"]
  #   relabel_configs:
  #     - source_labels: [__meta_docker_container_label_prometheus_io_port]
  #       target_label: __address__
  #       regex: (.+)
  #       replacement: "$1"
  #     - source_labels: [__meta_docker_container_name]
  #       target_label: container_name
  # -------------------------------------------------------------------------
