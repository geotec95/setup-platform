# CLAUDE.md

Instruções para o Claude Code (terminal) neste repositório. Leia junto com `HANDOFF.md` (contexto do que já foi feito) e `README.md` (documentação de uso).

## Idioma — regra obrigatória

**Sempre em português do Brasil, sem exceção**: respostas, explicações, comentários de código novo, mensagens de commit, perguntas de clarificação, e também o raciocínio/pensamento (thinking) do modelo. Nunca alterne para inglês no meio da resposta, mesmo citando termos técnicos (mantenha o termo técnico em inglês quando não houver tradução natural — ex: "deploy", "healthcheck" — mas a frase ao redor é em português).

## O que é este projeto

`setup-platform`: instalador modular estilo "setup manager" para VPS/EC2, em Bash. Objetivo final: automação (N8N), monitoramento de contas AWS (clone do FinOps Agent), observabilidade de aplicações dos clientes (Prometheus/Grafana/Loki) e dashboards white-label replicáveis por cliente.

Autor/dono do produto: George Junior (Arcus Cloud Security, Florianópolis/SC). Consultoria em infra cloud + produtos SaaS. Sempre responder em português do Brasil, direto ao ponto, sem explicar conceito básico de terminal/cloud/programação.

## AWS — regra obrigatória

**Sempre** que for criar, listar, ou acessar qualquer recurso AWS (CLI, boto3, Terraform, scripts), use:

```
AWS_PROFILE=geotec
AWS_DEFAULT_REGION=us-east-1
```

Nunca use `default` profile nem credenciais hardcoded. Se um comando AWS CLI for sugerido, sempre prefixe com `AWS_PROFILE=geotec` ou exporte a variável antes. Em scripts Python (boto3), sempre abra a sessão explicitamente com `boto3.Session(profile_name="geotec", region_name="us-east-1")` — nunca deixe cair no profile default do ambiente.

Se o usuário pedir para trabalhar com outra conta/profile, é uma exceção pontual — pergunte antes de assumir.

## Convenções do código (Bash)

- Todo script novo usa `set -Eeuo pipefail`.
- Funções pequenas, reutilizáveis, namespace `sp::` (core) ou `sp::aws::` (providers/aws).
- Sourcing sempre via `SP_ROOT` relativo ao próprio arquivo (ver qualquer `modules/*/install.sh` como referência) — nunca path absoluto hardcoded.
- Módulo novo = manifesto em `config/tools/<slug>.yaml` + `modules/<slug>/{install,uninstall,validate}.sh`, seguindo exatamente o padrão de `modules/n8n/`.
- Persistência sempre em `/data/<slug>`, nunca em volume Docker anônimo.
- Nunca credenciais/segredos hardcoded ou commitados — só `.env.example` no repo, `.env` real fica fora do Git.
- Deploy via Docker Swarm (`docker stack deploy`), não `docker-compose up` solto — o Traefik já assume Swarm mode.
- Painéis internos (Prometheus, Loki) nunca expostos publicamente; só o que tem label Traefik + HTTPS.

## Estrutura

```
setup-platform/
├── bin/            setup.sh (menu) e bootstrap.sh (instalador remoto via curl)
├── core/           common, os, docker, proxy, menu, logs, validate
├── providers/aws/  detect (IMDSv2), cost-report, security-report, backup-s3, route53, cloudwatch
├── config/         categories.yaml + config/tools/*.yaml (manifests)
├── modules/        1 pasta por ferramenta (n8n, observability, aws-monitor, client-dashboard)
├── templates/      compose, env, traefik, n8n-workflows, dashboards, wrapper HTML
└── scripts/        utilitários de dev/teste (fora do fluxo do instalador em si)
```

## Antes de rodar qualquer coisa

Os scripts `.sh` deste repo ainda não têm permissão de execução (`chmod +x`) — o ambiente onde foram gerados não tinha acesso de shell à pasta. Primeira coisa a fazer numa sessão nova:

```bash
chmod +x bin/*.sh core/*.sh providers/aws/*.sh modules/*/*.sh scripts/*.py
```

## Subagentes, commands e skills (`.claude/`)

Este repo já vem com tooling do Claude Code configurado em `.claude/`:

- **Subagentes** (`.claude/agents/`): `security-engineer`, `observability-engineer`, `devops-engineer` — acione via delegação automática ou chamando explicitamente (`@security-engineer`, etc.) quando a tarefa for claramente da área de um deles.
- **Commands** (`.claude/commands/`): `/comecar` (onboarding de sessão nova), `/seguranca` (varredura de segurança do repo), `/auditoria` (auditoria completa de conformidade dos módulos).
- **Skills** (`.claude/skills/`): `dashboard-design` (padrões de design pros dashboards/wrapper HTML), `novo-modulo` (scaffold de ferramenta nova seguindo o padrão `sp::`), `n8n-workflow` (construção/revisão de workflows n8n).

Use esses recursos em vez de reinventar o processo a cada sessão — eles já encapsulam as convenções deste projeto.

## Pendências conhecidas (ver HANDOFF.md para detalhes)

- Nada disso foi testado ponta a ponta numa EC2 real ainda.
- `bin/bootstrap.sh` só funciona depois de publicar este repo no Git e apontar `SP_REPO_URL`.
- `modules/client-dashboard` depende de `modules/observability` estar rodando.
