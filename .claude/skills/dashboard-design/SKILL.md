---
name: dashboard-design
description: Padrões de design (frontend + visual) para criar dashboards premium — o wrapper HTML branded do módulo client-dashboard e os dashboards JSON do Grafana. Use ao criar ou revisar qualquer coisa visual entregue ao cliente final.
---

# Dashboard Design — setup-platform

Diretrizes de design para tudo que é "cara" do produto entregue ao cliente: `templates/client-dashboard/wrapper.html.tpl` e os dashboards JSON do Grafana (`templates/observability/dashboards/*.json`, e os copiados por org em `modules/client-dashboard/new-client.sh`).

## Princípio central

O cliente final não usa Grafana no dia a dia — ele vê o **wrapper**. O wrapper é o produto. Precisa parecer um SaaS pago, não uma tela de admin de infra.

## Regras de visual (wrapper HTML)

- **Dark mode por padrão** — é o que fica "premium" em dashboards de monitoramento/infra (Datadog, Grafana Cloud, Vercel Analytics — todos dark por padrão). Light mode só como toggle opcional, nunca como padrão.
- **Zero build step**: HTML/CSS puro, sem framework pesado (o wrapper roda de um `nginx:alpine` simples, não precisa de Node/webpack). Pode usar CSS Grid/Flexbox nativo.
- **Identidade do cliente em 3 pontos só**: logo (header), cor de destaque via CSS var (`--client-primary-color`), nome do cliente no `<title>`. Não tente redesenhar o resto pra cada cliente — isso não escala.
- **Hierarquia visual**: header fixo (logo + nome do cliente + status geral em 1 badge verde/amarelo/vermelho) → grid de painéis (iframes do Grafana) → nada de rodapé pesado ou menu lateral desnecessário.
- **Responsivo**: grid que colapsa pra 1 coluna em mobile — muito cliente vai abrir isso no celular pra checar rápido.
- **Loading state**: os iframes do Grafana demoram a carregar — sempre mostrar um skeleton/spinner, nunca tela em branco.
- **Tipografia**: fonte de sistema (`-apple-system, Segoe UI, Roboto, sans-serif`) — não carregar Google Fonts externo, é peso desnecessário pra um dashboard interno.

## Regras de visual (dashboards Grafana / JSON)

- Painéis de série temporal: sempre com legenda e eixo Y com unidade correta (`%`, `bytes`, `ms`) — nunca número cru sem contexto.
- Cores de status seguem o semáforo padrão: verde = saudável, amarelo = atenção, vermelho = crítico. Não inventar paleta própria pra isso.
- Nomes de painel em português, direto ("CPU por container", não "Container CPU Usage (%) - all namespaces aggregated by pod").
- Todo dashboard novo precisa ter no mínimo: visão geral (status agregado no topo), detalhamento por recurso, e um painel de logs/eventos recentes — replica a estrutura de `docker-overview.json`.
- Ao criar dashboard novo, sempre validar o JSON (`apiVersion`, `panels[].type`, `templating`) antes de entregar — um JSON malformado quebra o provisionamento inteiro do Grafana.

## Checklist rápido antes de considerar um dashboard "pronto para cliente"

1. Abre em <2s numa conexão razoável (iframes lazy-loaded se tiver mais de 4).
2. Funciona em mobile.
3. Cor do cliente aplicada corretamente (não ficou cor genérica do template).
4. Nenhum termo técnico de infra sem necessidade ("pod", "namespace", "swarm") — traduza pra linguagem de negócio quando possível ("aplicação", "ambiente").
5. HTTPS válido no subdomínio do cliente (sem warning de certificado).
