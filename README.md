# setup-platform — Arcus Cloud Security

Instalador modular estilo "setup manager" para VPS/EC2, com foco em automação (N8N), monitoramento de contas AWS (FinOps), observabilidade de aplicações e dashboards white-label replicáveis por cliente.

Nasceu como resposta a um problema concreto: instaladores genéricos (ex: SetupOrion) detectam o IP privado da interface de rede, o que quebra em EC2 (o IP público é NAT feito pela AWS, não fica bindado na ENI). Este projeto resolve isso nativamente via IMDSv2 e já nasce pensado para produção na AWS.

## Comando único (depois de publicar o repo)

```bash
sudo bash <(curl -sSL setup.SEUDOMINIO.com.br)
```

Esse endpoint deve apenas servir o conteúdo de `bin/bootstrap.sh` (aponte um DNS/Cloudflare Worker/S3+CloudFront pra esse arquivo). Ele clona o repo em `/opt/setup-platform` e chama `bin/setup.sh`, que abre o menu interativo.

## Uso local (sem publicar ainda)

```bash
sudo bash bin/setup.sh
```

## Estrutura

```
setup-platform/
├── bin/            entrypoints (setup.sh = menu, bootstrap.sh = instalador remoto)
├── core/           funções reutilizáveis (common, os, docker, proxy, menu, logs, validate)
├── providers/aws/  detecção de ambiente EC2/IMDSv2, cost/security reports, s3, route53, cloudwatch
├── config/         categories.yaml + manifests YAML por ferramenta (config/tools/*.yaml)
├── modules/        1 pasta por ferramenta (install.sh, uninstall.sh, validate.sh)
├── templates/      compose, env, traefik, n8n-workflows, dashboards, wrapper HTML
├── logs/           log estruturado (setup-platform.log)
└── backups/        saída de backups locais antes do envio pro S3
```

## Ferramentas disponíveis nesta primeira leva

| Slug | Categoria | O que faz |
|---|---|---|
| `n8n` | automacao | Orquestrador — dispara os workflows de report e integra tudo |
| `observability` | observabilidade | Prometheus + Grafana + Loki + cAdvisor + node-exporter das apps dos clientes |
| `aws-monitor` | monitoramento_aws | Clone funcional do FinOps Agent: custo, recursos ociosos, security groups abertos, IAM sem MFA — envia report via n8n |
| `client-dashboard` | dashboard | Provisiona um dashboard branded por cliente (org isolada no Grafana + wrapper HTML com a marca do cliente) |

Ordem de instalação recomendada: **1) base do servidor → 2) Traefik → 3) n8n → 4) observability → 5) aws-monitor → 6) client-dashboard** (cada um checa suas dependências e avisa se algo faltar).

## Decisões de arquitetura importantes

- **IP público na AWS**: nunca confie em `hostname -I`. Use `sp::network::public_ip` (`providers/aws/detect.sh`), que resolve via IMDSv2 em EC2 e via `ifconfig.me` fora da AWS. Associe um **Elastic IP** — sem ele, o IP muda a cada stop/start e derruba DNS/SSL.
- **Segredos**: preferir IAM Instance Profile a chaves de acesso. Nunca commitar `.env` com valor real (só os `.env.example`).
- **Multi-tenant dos dashboards**: Grafana OSS não tem white-label nativo (é recurso Enterprise pago). A solução adotada é 1 Grafana compartilhado com 1 Organization por cliente + um wrapper HTML estático com a marca do cliente embutindo os painéis via iframe/public-dashboard. Documentado em `modules/client-dashboard/new-client.sh`.
- **Rede**: Prometheus e Loki nunca ficam expostos publicamente, só na rede overlay interna. Só o Grafana (e os painéis dos clientes) passam pelo Traefik com HTTPS.

## Próximos passos sugeridos

1. Publicar este diretório como repositório Git privado e ajustar `SP_REPO_URL` em `bin/bootstrap.sh`.
2. Rodar `chmod +x` em todos os `.sh` antes do primeiro commit (não foi possível fazer isso neste ambiente — o shell do sandbox não teve acesso ao caminho da pasta compartilhada).
3. Testar o fluxo ponta a ponta numa EC2 real: base → Traefik → n8n → observability → aws-monitor → client-dashboard.
4. Criar a IAM Role/Instance Profile na conta usando `providers/aws/iam-policy-aws-monitor.json`.
5. Adicionar Tempo (tracing distribuído) e Alertmanager como evolução do módulo `observability`.
6. Testar `new-client.sh` criando um cliente fictício e validando o subdomínio + wrapper.
