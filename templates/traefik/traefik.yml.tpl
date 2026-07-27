api:
  dashboard: true

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  swarm:
    exposedByDefault: false
    network: rede_publica
    endpoint: "unix:///var/run/docker.sock"

certificatesResolvers:
  letsencryptresolver:
    acme:
      email: "{{EMAIL}}"
      storage: /etc/traefik/letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

log:
  level: WARN
