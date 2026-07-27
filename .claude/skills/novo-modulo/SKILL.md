---
name: novo-modulo
description: Scaffold de uma ferramenta nova no setup-platform (manifesto + install/uninstall/validate), seguindo exatamente o padrão de modules/n8n. Use sempre que o usuário pedir para adicionar uma ferramenta nova ao instalador.
---

# Novo módulo — setup-platform

Checklist e template para adicionar uma ferramenta nova ao instalador, seguindo o padrão definido em `CLAUDE.md`.

## Passo a passo

1. **Leia primeiro** `modules/n8n/install.sh`, `uninstall.sh`, `validate.sh` e `config/tools/n8n.yaml` — é a referência canônica, copie a estrutura, não invente um padrão novo.
2. **Manifesto** em `config/tools/<slug>.yaml`:
   ```yaml
   name: <Nome Legível>
   slug: <slug>
   category: <uma das categorias em config/categories.yaml>
   description: "..."
   requires:
     - docker
     - reverse_proxy   # se expuser painel web
   ports:
     - "PORTA"
   domains:
     - "<slug>.SEUDOMINIO.com.br"   # omitir se for headless (ex: aws-monitor)
   env_required:
     - VAR_1
   volumes:
     - /data/<slug>
   install_strategy: docker_compose
   healthcheck:
     type: http
     url: "http://localhost:PORTA/health"
   validate_command: "docker ps --format '{{.Names}}' | grep -q '^<slug>_<slug>'"
   uninstall_strategy: docker_compose_down
   ```
3. **`modules/<slug>/install.sh`**: idempotência primeiro (`sp::is_stack_up "$SLUG" && exit 0`, exceto com `--update`), pedir domínio via `sp::proxy::ask_domain` se expuser painel, gerar `.env` com `sp::gen_password` para qualquer credencial, `sp::ensure_data_dir` para persistência, `sp::docker::ensure_network rede_publica`, `docker stack deploy` usando um compose em `templates/compose/<slug>.yml`.
4. **`templates/compose/<slug>.yml`**: Docker Swarm (não `docker-compose up`), labels Traefik idênticas ao padrão de `templates/compose/n8n.yml` se expuser painel, senão sem nenhuma label pública.
5. **`modules/<slug>/uninstall.sh`**: `sp::confirm` antes de remover, preserva `/data/<slug>` por padrão (pede confirmação separada pra apagar dados).
6. **`modules/<slug>/validate.sh`**: checagem simples de container/serviço rodando, exit code 0/1.
7. **`templates/env/<slug>.env.example`**: todas as variáveis de `env_required`, sem valor real.

## Regras que não podem ser quebradas

- `set -Eeuo pipefail` em todo `.sh` novo.
- Namespace `sp::` para toda função nova reutilizável (se for específica do módulo, prefixe `sp::<slug>::`).
- `SP_ROOT` sempre relativo via `$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)`.
- Nenhum path absoluto hardcoded, nenhuma credencial hardcoded.
- Se o módulo precisar de AWS, usar sempre `AWS_PROFILE=geotec` / `us-east-1` (ver `providers/aws/detect.sh` para funções já prontas — não reimplementar detecção de IP/instância).

## Depois de criar

- Rode o command `/auditoria` para conferir conformidade.
- Rode o subagente `security-engineer` se o módulo mexer com rede/segredos/IAM.
- Atualize `HANDOFF.md` com o que foi adicionado.
