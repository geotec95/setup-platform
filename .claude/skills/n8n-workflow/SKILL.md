---
name: n8n-workflow
description: Construção e revisão de workflows N8N (formato JSON de export) usados pelo setup-platform para orquestrar reports e automações. Use ao criar ou editar qualquer arquivo em templates/n8n-workflows/.
---

# Workflows N8N — setup-platform

O N8N é o orquestrador central da plataforma (módulo `n8n`) — dispara os reports do `aws-monitor` e futuras automações. Os workflows vivem como JSON exportado em `templates/n8n-workflows/*.json` e são importados via API REST (`POST /api/v1/workflows`, ver `modules/aws-monitor/install.sh` como referência) ou manualmente pela UI.

## Referência existente

Leia `templates/n8n-workflows/aws-finops-report.json` antes de criar um workflow novo — é o padrão: Schedule Trigger → Execute Command (roda script Bash local) → Merge → Code node (formata HTML) → nós de envio (Email/Slack).

## Padrões a seguir

- **Trigger**: prefira Schedule Trigger (cron) para reports periódicos. Webhook Trigger só quando precisar reagir a evento externo.
- **Execução de scripts**: nó "Execute Command" chamando os scripts já staged em `/data/<slug>/bin/` (ver `sp::aws_monitor::stage_scripts` como padrão) — nunca reimplemente lógica de coleta de dados dentro de um Code node do n8n, o script Bash já validado é a fonte de verdade.
- **Formatação**: Code node em JavaScript formatando JSON bruto em HTML legível — mantenha simples, sem dependência externa (n8n Code node roda sandboxed).
- **Credenciais**: nunca hardcode webhook URL / SMTP no JSON do workflow — use n8n Credentials (referenciadas por nome/ID) e deixe um placeholder comentado explicando o que configurar depois de importar.
- **Nomeação de nodes**: em português, descritivo ("Rodar Cost Report", não "Execute Command1").
- **Idempotência de import**: o script de instalação que importa via API deve checar se um workflow com aquele nome já existe antes de duplicar (ou aceitar que reimport atualiza).

## Checklist antes de considerar um workflow pronto

1. JSON válido (testar com `jq . arquivo.json` antes de entregar).
2. Todo node tem `position` definido (senão a UI do n8n empilha tudo em cima).
3. Credenciais sensíveis nunca em texto plano no JSON.
4. Trigger schedule documentado em comentário (ex: "semanal, segunda 08:00 America/Sao_Paulo").
5. Node final de envio tem fallback/log se o envio falhar (não deixar erro engolido silenciosamente).
