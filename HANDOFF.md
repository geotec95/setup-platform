# HANDOFF.md

Contexto de handoff para retomar este projeto numa sessão nova (Claude Code no terminal ou qualquer outra ferramenta). Escrito em 2026-07-26.

## Ponto de partida

O usuário usava o [SetupOrion](https://github.com/oriondesign2015/SetupOrion) (`bash <(curl -sSL setup.oriondesign.art.br)`) para instalar ferramentas self-hosted (N8N, Grafana, etc.) em VPS. Em EC2 da AWS, o instalador detectava o IP **privado** em vez do público, porque scripts genéricos usam `hostname -I`/`ip addr` — e na AWS o IP público é NAT feito fora da interface de rede, então isso nunca funciona bem numa EC2.

Em vez de remendar o script de terceiros, decidimos construir um instalador próprio, modular, do zero: o `setup-platform`.

## O que foi construído nesta sessão

Arquitetura 100% nova, seguindo a spec do projeto (ver `CLAUDE.md`). Todo o núcleo foi escrito diretamente; os 3 módulos de produto foram construídos por 3 subagentes em paralelo, cada um lendo o núcleo + o módulo `n8n` como referência de padrão antes de escrever código.

### 1. Núcleo (`bin/`, `core/`, `providers/aws/detect.sh`)
- `providers/aws/detect.sh`: resolve o bug do IP via **IMDSv2** (`sp::network::public_ip`) — detecta se é EC2, pega o IP público real via metadata service, com fallback pra `ifconfig.me` fora da AWS. Também tem `sp::aws::advise` (avisos de custo/segurança proativos: EIP não associado, Security Group aberto).
- `core/common.sh`: biblioteca de funções (`sp::ok/warn/err/info/log/confirm/ask/gen_password/ensure_data_dir/yaml_get` etc.) usada por tudo.
- `core/os.sh`, `core/docker.sh`, `core/proxy.sh` (Traefik + Let's Encrypt), `core/menu.sh` (menu gerado dinamicamente a partir dos manifests em `config/tools/*.yaml`), `core/logs.sh`, `core/validate.sh`.
- `bin/setup.sh`: entrypoint local (`sudo bash bin/setup.sh`).
- `bin/bootstrap.sh`: o que vai virar o "comando único" (`bash <(curl -sSL setup.SEUDOMINIO.com.br)`) — ainda **não publicado**, precisa de um repo Git + domínio apontando pra esse arquivo.

### 2. Módulo `n8n` (referência de padrão)
Instala N8N via Docker Swarm + Traefik/HTTPS. Todo módulo novo copia esse padrão.

### 3. Módulo `aws-monitor` (clone do AWS FinOps Agent)
- `providers/aws/cost-report.sh`: custo 7d/30d, variação %, top 10 serviços, recursos ociosos (EIPs órfãos, EBS não anexado, instâncias paradas), status de budgets.
- `providers/aws/security-report.sh`: Security Groups abertos em portas sensíveis, IAM sem MFA, access keys >90 dias, buckets S3 públicos, Security Hub/Trusted Advisor quando disponível.
- `providers/aws/backup-s3.sh`, `route53.sh`, `cloudwatch.sh`: helpers genéricos reutilizáveis por qualquer módulo.
- `providers/aws/iam-policy-aws-monitor.json`: política IAM de menor privilégio (anexar via Instance Profile, nunca via chave hardcoded).
- `templates/n8n-workflows/aws-finops-report.json`: workflow N8N pronto pra importar (schedule semanal → roda os scripts → formata HTML → envia por e-mail/Slack).
- `modules/aws-monitor/install.sh` tenta importar esse workflow automaticamente via API do n8n.

### 4. Módulo `observability`
Prometheus + Grafana + Loki + Promtail + cAdvisor + node-exporter via Docker Swarm. Só o Grafana fica exposto (Traefik/HTTPS); Prometheus e Loki ficam só na rede interna. Dashboard básico já provisionado automaticamente (`templates/observability/dashboards/docker-overview.json`).

### 5. Módulo `client-dashboard` (dashboard premium multi-cliente)
Decisão de arquitetura: Grafana OSS não tem white-label nativo (é recurso Enterprise pago). Solução adotada: **1 Grafana compartilhado** (o do módulo `observability`) com **1 Organization por cliente** (isolamento via Grafana Orgs API) + um **wrapper HTML estático** com a marca do cliente (logo, cor) embutindo os painéis via iframe/public-dashboard. Cada cliente ganha subdomínio próprio + HTTPS via Traefik.

Uso: `bash modules/client-dashboard/new-client.sh <slug-cliente> <dominio-cliente> <cor-hex> <url-logo>`.

## O que NÃO foi feito ainda

- **Nada foi testado numa EC2 real.** O ambiente onde isso foi gerado não tinha acesso de shell à pasta do projeto (erro de path UNC), então não rodamos `chmod +x`, não subimos containers, não validamos o fluxo ponta a ponta.
- `bin/bootstrap.sh` não está publicado — falta criar o repo Git (GitHub) e apontar um domínio/endpoint pra ele.
- Tracing distribuído (Tempo) e Alertmanager foram citados como próxima iteração do módulo `observability`, mas não implementados.
- `client-dashboard` usa Grafana public-dashboards (iframe sem autenticação forte) — ok pra MVP, mas documentado como trade-off a revisitar se algum cliente exigir mais segurança.

## Próximos passos sugeridos (em ordem)

1. `chmod +x bin/*.sh core/*.sh providers/aws/*.sh modules/*/*.sh` (ver `CLAUDE.md`).
2. Subir uma EC2 de teste — ver `scripts/create_test_ec2.py` (criado junto com este handoff, usa `AWS_PROFILE=geotec`, `us-east-1`).
3. Rodar `sudo bash bin/setup.sh` na EC2 de teste, instalar na ordem: base do servidor → Traefik → n8n → observability → aws-monitor → client-dashboard.
4. Validar que `sp::network::public_ip` realmente resolve o IP público correto (esse era o bug original).
5. Criar a IAM Role/Instance Profile na conta `geotec` usando `providers/aws/iam-policy-aws-monitor.json` e anexar na instância de teste.
6. Depois de validar, publicar o repo no GitHub e configurar `SP_REPO_URL` em `bin/bootstrap.sh` + domínio apontando pra ele.
