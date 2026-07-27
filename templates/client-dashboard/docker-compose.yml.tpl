# templates/client-dashboard/docker-compose.yml.tpl
# Serviço estático (nginx:alpine) que serve o wrapper.html já personalizado do
# cliente. Um stack Swarm por cliente, nomeado "clientdash-{{CLIENT_SLUG}}",
# para permitir remover/atualizar um cliente sem afetar os demais.
# Variáveis substituídas por new-client.sh (sed):
#   {{CLIENT_SLUG}}   - identificador curto do cliente (a-z0-9-)
#   {{CLIENT_DOMAIN}} - domínio público do cliente (Host() do Traefik)
version: "3.8"

services:
  web:
    image: nginx:alpine
    networks:
      - rede_publica
    volumes:
      - /data/client-dashboard/{{CLIENT_SLUG}}/html:/usr/share/nginx/html:ro
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.clientdash-{{CLIENT_SLUG}}.rule=Host(`{{CLIENT_DOMAIN}}`)"
        - "traefik.http.routers.clientdash-{{CLIENT_SLUG}}.entrypoints=websecure"
        - "traefik.http.routers.clientdash-{{CLIENT_SLUG}}.tls.certresolver=letsencryptresolver"
        - "traefik.http.services.clientdash-{{CLIENT_SLUG}}.loadbalancer.server.port=80"
      placement:
        constraints:
          - node.role == manager

networks:
  rede_publica:
    external: true
