# templates/remote-agent/prometheus-agent.yml.tpl
# Config do Prometheus rodando em modo "agent" (--enable-feature=agent):
# só faz scrape local + remote_write, sem storage/query própria. O label
# "client" é anexado a TODA métrica antes de sair daqui, pra diferenciar
# este cliente dentro do Prometheus central compartilhado.
global:
  scrape_interval: 30s
  external_labels:
    client: "{{CLIENT_LABEL}}"

scrape_configs:
  - job_name: node-exporter
    static_configs:
      - targets: ["node-exporter:9100"]

  - job_name: cadvisor
    static_configs:
      - targets: ["cadvisor:8080"]

remote_write:
  - url: "https://{{CENTRAL_INGEST_DOMAIN}}/api/v1/write"
    basic_auth:
      username: "{{INGEST_USER}}"
      password: "{{INGEST_PASSWORD}}"
