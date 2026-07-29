# HANDOFF.md

Contexto de handoff para retomar este projeto numa sessão nova (Claude Code no terminal ou qualquer outra ferramenta). Escrito originalmente em 2026-07-26, reescrito em 2026-07-29 após várias sessões de expansão — o projeto saiu de "instalador modular" pra "produto SaaS multi-cliente em produção real".

## Ponto de partida (histórico)

O usuário usava o [SetupOrion](https://github.com/oriondesign2015/SetupOrion) pra instalar ferramentas self-hosted em VPS. Em EC2 da AWS, o instalador detectava o IP **privado** em vez do público (scripts genéricos usam `hostname -I`, e na AWS o IP público é NAT fora da interface de rede). Em vez de remendar o script de terceiros, construímos um instalador próprio do zero: o `setup-platform`.

## Estado atual: em produção real

Isto não é mais só um instalador — hoje roda de verdade em duas EC2s:

- **EC2 central** (conta `geotec`, perfil AWS `geotec`, `i-05fd28179b086c305`): n8n, Grafana/Prometheus/Loki/Tempo (observability), central-admin, gotenberg, evolution-api, uptime-kuma.
- **EC2 do cliente WRI/AMZ BIOECON** (conta `remap`, perfil AWS `remap`, `i-0f1878229ca3ed754`, nome da instância `wri-bioeconomy-backend-development`): `remote-agent` empurrando métricas/logs pro observability central.
- Domínios reais: `grafana.arcuscloud.com.br`, `ingest.arcuscloud.com.br`, `central.arcuscloud.com.br`, `wri.arcuscloud.com.br`, `n8n.arcuscloud.com.br` — todos com Cloudflare Access na frente (exceto o endpoint de ingestão, que usa Basic Auth).

## Módulos existentes (`modules/`)

| Módulo | O que faz |
|---|---|
| `n8n` | Automação (referência de padrão pros demais módulos) |
| `aws-monitor` | Clone do AWS FinOps Agent (custo, segurança, recursos ociosos) |
| `observability` | Prometheus + Grafana + Loki + Tempo + Promtail + cAdvisor + node-exporter, multi-org por cliente |
| `client-dashboard` | Provisiona 1 cliente novo: org Grafana + wrapper HTML white-label + workflow n8n de relatório |
| `remote-agent` | Agente leve (Prometheus agent + Promtail + cAdvisor + node-exporter) pra instalar na EC2 do CLIENTE, empurra tudo pro observability central via HTTPS |
| `evolution-api` | Gateway WhatsApp self-hosted (alertas via WhatsApp) |
| `uptime-kuma` | Uptime/disponibilidade de frontend e backend do cliente |
| `gotenberg` | Conversor HTML→PDF self-hosted (usado pelo relatório mensal) |
| `central-admin` | Área administrativa (`central.arcuscloud.com.br`): formulário que cria cliente novo automaticamente — DNS, Cloudflare Access, dashboard, workflow de relatório |

## Funcionalidades entregues (além da infra básica)

### Dashboard de cliente (`client-dashboard` + wrapper)
- 5 abas: Visão Geral, Métricas, Traces, Logs, **Relatório**.
- Co-branding real: logo do cliente + logo da Remap lado a lado no header (não é mais ícone genérico).
- Painel "Visão Geral" com rótulos revisados (ex: "Sondas de monitoramento ativas" em vez de "Serviços online", que confundia o cliente).
- Aba "Logs" tem geolocalização de IP de origem (ver seção própria abaixo).
- Aba "Relatório": botão "Gerar relatório agora" (dispara workflow n8n via webhook) + histórico de envios mês a mês (consulta `/api/v1/executions` do n8n via workflow `report-history-api.json`).

### Relatório mensal em PDF (`templates/n8n-workflows/monthly-client-report.json`)
- Redação executiva institucional (sem coloquialismo, distingue disponibilidade / volume técnico / uso real).
- Identidade visual real da Remap Geotecnologia (Brand Book: paleta, tipografia Ubuntu embutida via `@font-face` base64, textura).
- Logos reais do cliente + Remap lado a lado.
- Disponibilidade por camada (Frontend/Backend via Uptime Kuma).
- PDF gerado via Gotenberg (headless Chromium), nome do arquivo anexado = `<nome do cliente> - <mês>.pdf`.
- Cada cliente tem seu próprio clone do workflow (feito a partir do template `GQ2SGg5l07P26Hq9`, nunca ativado).

### Provisionamento automático (`central-admin` + `provision-client.json`)
Formulário em `central.arcuscloud.com.br` → webhook n8n → cria em paralelo: DNS Cloudflare + Cloudflare Access App/Policy, e workflow de relatório do cliente + org Grafana + wrapper via SSM (`new-client.sh`). Testado 2x de ponta a ponta com sucesso.

### Geolocalização de IP de origem (mais recente, 2026-07-29)
- Base MaxMind GeoLite2-City baixada via license key (`.env`, nunca commitada).
- Promtail extrai `remote_addr` do log de acesso HTTP (regex), geolocaliza via stage nativo `geoip`, anexa país/cidade/coordenadas como **structured metadata** do Loki (não label — evita explosão de cardinalidade).
- Painéis "Requisições por país" e "Top IPs de origem" na aba Logs, como consulta **instantânea** de verdade (`queryType: instant` + `range: false` — só `instant: true` sozinho não bastava, o Grafana ainda rodava como série temporal).
- Aplicado tanto no `observability` quanto no `remote-agent` — feature opcional via placeholder `{{GEOIP_STAGES}}` (sem `MAXMIND_LICENSE_KEY`, vira comentário e nada muda).

## Bugs reais encontrados e corrigidos nesta fase (vale saber pra não repetir)

- **Datasources não compartilhados entre orgs do Grafana** — cada org precisa da própria cópia.
- **`--update` do client-dashboard nunca trocava nome/logo/cor** — o `source` do `.env` genérico sobrescrevia as variáveis recém-digitadas; corrigido isolando em subshell.
- **`topk` de endpoints incluía o próprio agente de monitoramento** como se fosse uso real — corrigido com filtro de exclusão na query PromQL.
- **403 no central-admin** — pasta criada com permissão 750, nginx roda non-root; corrigido com `chmod -R a+rX`.
- **Cloudflare Access não interceptava tráfego** — registro DNS estava "DNS only" (`proxied: false`); Access só funciona com proxy ativo.
- **Dashboards `client-*.json` nunca eram copiados pelo `install.sh` do observability** — só existiam na EC2 porque foram colocados manualmente numa sessão anterior; uma instalação do zero teria falhado. Corrigido.
- **Indentação YAML errada no bloco geoip** — derrubava o Promtail inteiro em loop de erro de parse.
- **`geoip` e `structured_metadata` juntos no mesmo stage** — IP privado sem match na base MaxMind fazia o lookup falhar e arrastava junto a perda do `remote_addr` que já tinha sido extraído. Corrigido separando em dois stages.
- **Disco da EC2 central em 94%** (imagens Docker duplicadas/antigas, 14GB) — causava o ingester do Loki entrar em loop de "shutting down" e recusar logs. Resolvido com `docker image prune -a` (voltou pra 79%). **Vale monitorar isso periodicamente — não há alerta de disco configurado ainda.**
- **`instant: true` sozinho não faz o Grafana rodar como consulta instantânea** — precisa de `queryType: "instant"` + `range: false` junto, senão os painéis de tabela mostram série temporal (uma linha por timestamp) em vez de uma linha por grupo.

## Pendências conhecidas / dívida técnica

- Org "Cliente: Cliente Teste 2" (id 4) no Grafana é lixo de teste — a API recusou deletar, remoção manual pendente.
- Org "AMZ BIOECON" tem **5 cópias duplicadas** do dashboard "Logs" (de reinstalações/testes anteriores) — não quebra nada, mas é sujeira a limpar.
- Não há alerta de espaço em disco na própria EC2 (o incidente do Loki em 94% só foi pego por investigação manual).
- Retenção do Loki fixa em 30 dias pra todo mundo (não é por contrato/tier).
- `bin/bootstrap.sh` ainda não publicado (falta `SP_REPO_URL` apontando pro repo real).

## Próximos passos sugeridos (em ordem)

1. **Validar o que já foi construído em produção por um tempo** (decisão explícita do usuário em 2026-07-29: manter como está antes de adicionar mais coisa) — observar geolocalização, alertas e relatório mensal funcionando de verdade por pelo menos um ciclo antes de expandir.
2. **Configurar alerta de disco** na EC2 central (e, idealmente, em qualquer EC2 de cliente rodando `remote-agent`) — o incidente do Loki mostrou que isso é um ponto cego real.
3. Limpar a dívida técnica listada acima (org de teste órfã, dashboards duplicados).
4. Avaliar geolocalização com tráfego público real (hoje só tráfego interno passou pelo pipeline — país/cidade ainda não foram vistos preenchidos de verdade).
5. **IA no monitoramento** (discutido em 2026-07-29, não iniciado): antes de um chat interativo livre, começar pelo uso de menor risco — resumo automático de incidente gerado a partir dos dados que o próprio alerta já buscou (não alucina número, só sumariza o que a automação já coletou). Chat livre só depois, com isolamento por cliente desenhado desde o início (nunca confiar em `client_slug` vindo do front-end).
6. Dashboard central com visão agregada de todos os clientes (item do plano original do `central-admin`, ainda não implementado).
7. Publicar `bin/bootstrap.sh` (repo Git + domínio apontando pra ele) — pendência antiga, ainda não crítica.
8. Considerar SLA/SLO formal (meta contratual vs realizado) integrado ao relatório mensal, e status page pública via Uptime Kuma.
