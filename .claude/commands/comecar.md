---
description: Onboarding de sessão nova — carrega contexto do projeto e mostra status atual
---

Responda sempre em português do Brasil. Faça o seguinte, nesta ordem, e reporte de forma objetiva (sem enrolação):

1. Leia `CLAUDE.md` e `HANDOFF.md` na raiz do repo por completo.
2. Rode `chmod +x bin/*.sh core/*.sh providers/aws/*.sh modules/*/*.sh scripts/*.py 2>/dev/null` para garantir que os scripts são executáveis.
3. Liste o conteúdo de `config/tools/*.yaml` e mostre uma tabela rápida: slug, categoria, descrição, se `modules/<slug>/{install,uninstall,validate}.sh` existem todos.
4. Confira se `aws sts get-caller-identity --profile geotec` funciona (sem vazar nenhum dado sensível na resposta, só confirmar que autenticou e em qual conta).
5. Resuma em até 10 linhas: o que já está pronto, o que falta testar, e qual é o próximo passo mais lógico dado o estado atual (normalmente: subir a EC2 de teste com `scripts/create_test_ec2.py` e rodar `bin/setup.sh`).

Não refaça trabalho já feito — este comando é só para carregar contexto e dar o próximo passo, não para reescrever nada.
