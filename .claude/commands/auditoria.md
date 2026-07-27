---
description: Auditoria completa de conformidade dos módulos com o padrão do setup-platform
---

Responda sempre em português do Brasil. Para cada manifesto em `config/tools/*.yaml`, verifique e reporte em formato de tabela:

1. O manifesto tem todos os campos obrigatórios (`name, slug, category, description, requires, ports, env_required, volumes, install_strategy, healthcheck, validate_command, uninstall_strategy`) — igual à checagem de `core/validate.sh:sp::validate::manifest`.
2. Existe `modules/<slug>/install.sh`, `uninstall.sh` e `validate.sh`.
3. `install.sh` é idempotente (checa antes de criar — procure por `sp::is_stack_up`, checagem de `.env` existente, ou lookup via API antes de qualquer `create`).
4. `install.sh` usa `sp::ensure_data_dir` para persistência em `/data/<slug>` (nunca volume anônimo).
5. Se o módulo expõe painel web, confirme labels Traefik + HTTPS (`certresolver=letsencryptresolver`).
6. `category` do manifesto existe em `config/categories.yaml`.
7. Todo Bash novo tem `set -Eeuo pipefail` na primeira linha executável.
8. Nenhum segredo hardcoded (senhas via `sp::gen_password`, nunca string fixa).

Ao final, dê uma nota geral de conformidade por módulo (OK / atenção / bloqueante) e liste, em ordem de prioridade, o que precisa ser corrigido antes de considerar o módulo pronto para produção. Se algo não puder ser verificado sem rodar numa EC2 real (ex: healthcheck respondendo), diga isso explicitamente em vez de assumir que está ok.
