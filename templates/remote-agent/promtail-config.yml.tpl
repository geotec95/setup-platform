# templates/remote-agent/promtail-config.yml.tpl
# Mesma lógica de descoberta de containers do templates/observability/promtail-config.yml,
# mas os logs são empurrados (push) para o Loki central via HTTPS + Basic Auth,
# em vez de para um Loki local — e cada linha ganha o label "client" fixo.
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /tmp/positions.yaml

clients:
  - url: "https://{{CENTRAL_INGEST_DOMAIN}}/loki/api/v1/push"
    basic_auth:
      username: "{{INGEST_USER}}"
      password: "{{INGEST_PASSWORD}}"
    external_labels:
      client: "{{CLIENT_LABEL}}"

scrape_configs:
  - job_name: containerlogs
    docker_sd_configs:
      - host: unix:///var/run/docker.sock
        refresh_interval: 5s
    relabel_configs:
      # job_name não vira label "job" automaticamente em docker_sd_configs —
      # precisa ser setado explicitamente (ver templates/observability/promtail-config.yml).
      - target_label: job
        replacement: containerlogs
      - source_labels: [__meta_docker_container_name]
        regex: '/(.*)'
        target_label: container
      - source_labels: [__meta_docker_container_label_com_docker_swarm_service_name]
        target_label: swarm_service
      - source_labels: [__meta_docker_container_log_stream]
        target_label: stream
    pipeline_stages:
      # Mesmo tratamento do observability/promtail-config.yml: desembrulha o
      # envelope JSON do Docker e extrai um label "level" por heurística de
      # palavra-chave (não dá pra exigir formato estruturado de cada cliente).
      - docker: {}
      - regex:
          expression: '(?i)\b(?P<level>trace|debug|info|warn(?:ing)?|error|fatal|panic|critical)\b'
      - template:
          source: level
          template: '{{ ToLower .Value | replace "warning" "warn" | replace "critical" "error" | replace "panic" "fatal" }}'
      - labels:
          level:
      # Mesmo tratamento do observability/promtail-config.yml: extrai o IP de
      # origem só quando a linha tem formato de log de acesso HTTP. Também
      # tolera X-Forwarded-For com múltiplos IPs separados por vírgula
      # (comum em app atrás de load balancer) -- pega sempre o primeiro.
      - regex:
          expression: '^(?P<remote_addr>\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})(?:,\s*[\d.,\s]+)?\s\S+\s\S+\s\[.+?\]\s"(?P<http_method>[A-Z]+)\s(?P<request_path>\S+)'
{{GEOIP_STAGES}}
