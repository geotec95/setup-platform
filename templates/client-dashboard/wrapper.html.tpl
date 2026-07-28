<!-- templates/client-dashboard/wrapper.html.tpl
     Shell estático "premium" com a marca do cliente, sem framework/build step.
     Variáveis substituídas por new-client.sh (sed):
       {{CLIENT_NAME}}          - nome do cliente (título/alt do logo)
       {{CLIENT_LOGO_URL}}      - URL pública do logo do cliente
       {{CLIENT_PRIMARY_COLOR}} - cor de destaque em hex (ex: #0EA5E9)
       {{CLIENT_DOMAIN}}        - domínio final (usado no rodapé/meta)
       {{TAB_OVERVIEW_PANELS}}  - painéis da aba "Visão Geral" (client-overview.json)
       {{TAB_METRICS_PANELS}}   - painéis da aba "Métricas" (client-metrics.json)
       {{TAB_TRACES_PANELS}}    - painéis da aba "Traces" (client-traces.json)
       {{TAB_LOGS_PANELS}}      - painéis da aba "Logs" (client-logs.json)
       {{REPORT_GENERATE_URL}}  - webhook n8n que dispara o relatório mensal
                                  sob demanda (path único por cliente, ver
                                  modules/client-dashboard/new-client.sh)
       {{REPORT_HISTORY_URL}}   - webhook n8n compartilhado que devolve o
                                  histórico de envios (?workflow_id=X já
                                  embutido na URL por new-client.sh)
       {{REMAP_LOGO_DATA_URI}}  - logo da Remap embutida (data URI), fixa
                                  pra todo cliente (ver new-client.sh) --
                                  co-branding igual ao usado no PDF
     Cada bloco de painéis é HTML já pronto com um <div class="panel-card">
     por painel (título + iframe), gerado por new-client.sh. Só a aba ativa
     carrega os iframes (data-src -> src no clique), pra não puxar Grafana
     4x na primeira visita. -->
<!DOCTYPE html>
<html lang="pt-br">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>{{CLIENT_NAME}} — Dashboard</title>
<link rel="icon" href="{{CLIENT_LOGO_URL}}">
<style>
  :root {
    --client-primary: {{CLIENT_PRIMARY_COLOR}};
    --bg-base: #0a0c11;
    --bg-panel: #12151d;
    --bg-panel-header: #161a24;
    --bg-header: #0d0f15;
    --border-color: #232838;
    --border-color-soft: #1a1e2a;
    --text-main: #e8eaef;
    --text-muted: #838da3;
    --ok: #34d399;
  }

  * { box-sizing: border-box; }

  body {
    margin: 0;
    background:
      radial-gradient(1200px 480px at 15% -10%, color-mix(in srgb, var(--client-primary) 10%, transparent), transparent 60%),
      var(--bg-base);
    color: var(--text-main);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    -webkit-font-smoothing: antialiased;
  }

  header {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 14px 32px;
    background: color-mix(in srgb, var(--bg-header) 88%, transparent);
    backdrop-filter: blur(10px);
    border-bottom: 1px solid var(--border-color);
    position: sticky;
    top: 0;
    z-index: 20;
  }

  header::after {
    content: "";
    position: absolute;
    left: 0; right: 0; bottom: -1px;
    height: 2px;
    background: linear-gradient(90deg, var(--client-primary), transparent 70%);
  }

  .client-brand {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .client-brand img {
    height: 32px;
    width: auto;
    object-fit: contain;
  }

  header h1 {
    font-size: 15px;
    font-weight: 600;
    margin: 0;
    color: var(--text-main);
    letter-spacing: -0.01em;
  }

  header h1 small {
    display: block;
    font-size: 11px;
    font-weight: 400;
    color: var(--text-muted);
    margin-top: 2px;
  }

  .header-right {
    margin-left: auto;
    display: flex;
    align-items: center;
    gap: 14px;
  }

  .partner-brand {
    display: flex;
    align-items: center;
    padding-right: 14px;
    border-right: 1px solid var(--border-color);
  }

  .partner-brand img {
    height: 22px;
    width: auto;
    display: block;
    background: #fff;
    border-radius: 6px;
    padding: 4px 8px;
  }

  .status-badge {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    font-size: 12px;
    color: var(--text-muted);
    border: 1px solid var(--border-color);
    background: var(--bg-panel);
    border-radius: 999px;
    padding: 6px 14px 6px 10px;
  }

  .status-dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--ok);
    box-shadow: 0 0 0 0 rgba(52, 211, 153, 0.6);
    animation: pulse 2.4s ease-out infinite;
  }

  @keyframes pulse {
    0%   { box-shadow: 0 0 0 0 rgba(52, 211, 153, 0.55); }
    70%  { box-shadow: 0 0 0 7px rgba(52, 211, 153, 0); }
    100% { box-shadow: 0 0 0 0 rgba(52, 211, 153, 0); }
  }

  nav.tabs {
    display: flex;
    gap: 4px;
    padding: 0 32px;
    background: var(--bg-header);
    border-bottom: 1px solid var(--border-color);
    position: sticky;
    top: 61px;
    z-index: 19;
    overflow-x: auto;
  }

  nav.tabs button {
    appearance: none;
    background: none;
    border: none;
    color: var(--text-muted);
    font: inherit;
    font-size: 13px;
    font-weight: 600;
    padding: 12px 16px 10px;
    cursor: pointer;
    border-bottom: 2px solid transparent;
    white-space: nowrap;
    transition: color 0.15s ease;
  }

  nav.tabs button:hover { color: var(--text-main); }

  nav.tabs button.active {
    color: var(--text-main);
    border-bottom-color: var(--client-primary);
  }

  main {
    padding: 28px 32px 56px;
    max-width: 1600px;
    margin: 0 auto;
  }

  .tab-panel { display: none; }
  .tab-panel.active { display: block; }

  .empty-tab {
    color: var(--text-muted);
    font-size: 13px;
    border: 1px dashed var(--border-color);
    border-radius: 12px;
    padding: 32px;
    text-align: center;
  }

  .panels-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(440px, 1fr));
    gap: 20px;
  }

  .panel-card {
    background: var(--bg-panel);
    border: 1px solid var(--border-color-soft);
    border-radius: 12px;
    overflow: hidden;
    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.2), 0 12px 32px -16px rgba(0, 0, 0, 0.5);
    transition: border-color 0.2s ease, transform 0.2s ease;
  }

  .panel-card:hover {
    border-color: color-mix(in srgb, var(--client-primary) 35%, var(--border-color));
    transform: translateY(-1px);
  }

  .panel-card-header {
    display: flex;
    align-items: center;
    padding: 12px 16px;
    border-bottom: 1px solid var(--border-color-soft);
    background: var(--bg-panel-header);
  }

  .panel-card-header .dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--client-primary);
    margin-right: 10px;
    flex-shrink: 0;
  }

  .panel-title {
    font-size: 13px;
    font-weight: 600;
    color: var(--text-main);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .panel-card-body {
    position: relative;
    /* cada card embute um dashboard inteiro do Grafana (vários painéis
       empilhados), não um painel avulso -- precisa de bastante altura */
    height: calc(100vh - 190px);
    min-height: 480px;
  }

  .panel-card iframe {
    width: 100%;
    height: 100%;
    border: 0;
    display: block;
    background: var(--bg-panel);
    position: relative;
    z-index: 1;
  }

  .skeleton {
    position: absolute;
    inset: 0;
    z-index: 2;
    background:
      linear-gradient(100deg, var(--bg-panel) 40%, var(--bg-panel-header) 50%, var(--bg-panel) 60%);
    background-size: 200% 100%;
    animation: shimmer 1.4s ease-in-out infinite;
  }

  @keyframes shimmer {
    0%   { background-position: 120% 0; }
    100% { background-position: -20% 0; }
  }

  @media (prefers-reduced-motion: reduce) {
    .skeleton, .status-dot { animation: none; }
  }

  .report-panel { max-width: 720px; }

  .report-generate {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 20px;
    background: var(--bg-panel);
    border: 1px solid var(--border-color-soft);
    border-radius: 12px;
    padding: 20px 24px;
    margin-bottom: 16px;
  }

  .report-generate h2 {
    font-size: 15px;
    margin: 0 0 6px;
    color: var(--text-main);
  }

  .report-generate p {
    font-size: 13px;
    color: var(--text-muted);
    margin: 0;
    max-width: 46ch;
    line-height: 1.5;
  }

  #btn-generate-report {
    appearance: none;
    border: none;
    border-radius: 8px;
    background: var(--client-primary);
    color: #fff;
    font: inherit;
    font-size: 13px;
    font-weight: 600;
    padding: 11px 18px;
    cursor: pointer;
    white-space: nowrap;
    transition: opacity 0.15s ease;
  }

  #btn-generate-report:hover { opacity: 0.88; }
  #btn-generate-report:disabled { opacity: 0.55; cursor: default; }

  .report-status {
    font-size: 13px;
    border-radius: 8px;
    padding: 10px 14px;
    margin-bottom: 20px;
  }

  .report-status.ok { background: rgba(52, 211, 153, 0.12); color: var(--ok); border: 1px solid rgba(52, 211, 153, 0.3); }
  .report-status.err { background: rgba(239, 68, 68, 0.12); color: #f87171; border: 1px solid rgba(239, 68, 68, 0.3); }

  .report-panel h3 {
    font-size: 13px;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--text-muted);
    margin: 0 0 10px;
  }

  .report-history { display: flex; flex-direction: column; gap: 8px; }

  .report-history-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    background: var(--bg-panel);
    border: 1px solid var(--border-color-soft);
    border-radius: 10px;
    padding: 12px 16px;
    font-size: 13px;
  }

  .report-history-row .when { color: var(--text-main); }
  .report-history-row .when small { display: block; color: var(--text-muted); font-size: 11px; margin-top: 2px; }

  .report-history-status {
    font-size: 11px;
    font-weight: 600;
    padding: 3px 10px;
    border-radius: 999px;
  }

  .report-history-status.ok { background: rgba(52, 211, 153, 0.14); color: var(--ok); }
  .report-history-status.bad { background: rgba(239, 68, 68, 0.14); color: #f87171; }

  footer {
    text-align: center;
    padding: 28px 24px;
    color: var(--text-muted);
    font-size: 12px;
  }

  footer a {
    color: var(--client-primary);
    text-decoration: none;
  }

  footer a:hover { text-decoration: underline; }

  @media (max-width: 640px) {
    header { padding: 12px 16px; }
    header h1 { font-size: 13px; }
    .partner-brand { padding-right: 8px; }
    .partner-brand img { height: 18px; }
    nav.tabs { padding: 0 16px; top: 57px; }
    main { padding: 16px; }
    .panels-grid { grid-template-columns: 1fr; }
    .panel-card-body { height: 70vh; min-height: 420px; }
  }
</style>
</head>
<body>
  <header>
    <div class="client-brand">
      <img src="{{CLIENT_LOGO_URL}}" alt="{{CLIENT_NAME}}">
      <h1>{{CLIENT_NAME}}<small>Painel de monitoramento</small></h1>
    </div>
    <div class="header-right">
      <div class="partner-brand" title="Remap Geotecnologia">
        <img src="{{REMAP_LOGO_DATA_URI}}" alt="Remap Geotecnologia">
      </div>
      <span class="status-badge"><span class="status-dot"></span>Operacional</span>
    </div>
  </header>

  <nav class="tabs" role="tablist">
    <button type="button" class="active" data-tab="overview" role="tab" aria-selected="true">Visão Geral</button>
    <button type="button" data-tab="metrics" role="tab" aria-selected="false">Métricas</button>
    <button type="button" data-tab="traces" role="tab" aria-selected="false">Traces</button>
    <button type="button" data-tab="logs" role="tab" aria-selected="false">Logs</button>
    <button type="button" data-tab="report" role="tab" aria-selected="false">Relatório</button>
  </nav>

  <main>
    <div class="tab-panel active" id="tab-overview">
      <div class="panels-grid">
        {{TAB_OVERVIEW_PANELS}}
      </div>
    </div>
    <div class="tab-panel" id="tab-metrics">
      <div class="panels-grid">
        {{TAB_METRICS_PANELS}}
      </div>
    </div>
    <div class="tab-panel" id="tab-traces">
      <div class="panels-grid">
        {{TAB_TRACES_PANELS}}
      </div>
    </div>
    <div class="tab-panel" id="tab-logs">
      <div class="panels-grid">
        {{TAB_LOGS_PANELS}}
      </div>
    </div>
    <div class="tab-panel" id="tab-report">
      <div class="report-panel">
        <div class="report-generate">
          <div>
            <h2>Relatório mensal em PDF</h2>
            <p>Gere o relatório de performance sob demanda, a qualquer momento &mdash; ele é enviado por e-mail para o contato cadastrado. Um envio automático também acontece todo dia 1 do mês.</p>
          </div>
          <button type="button" id="btn-generate-report">Gerar relatório agora</button>
        </div>
        <div id="report-status" class="report-status" hidden></div>

        <h3>Histórico de envios</h3>
        <div id="report-history-list" class="report-history">
          <div class="empty-tab">Carregando histórico&hellip;</div>
        </div>
      </div>
    </div>
  </main>

  <footer>
    Powered by Arcus Cloud Security &middot; <a href="https://{{CLIENT_DOMAIN}}">{{CLIENT_DOMAIN}}</a>
  </footer>

  <script>
    (function () {
      function activateTab(name) {
        document.querySelectorAll("nav.tabs button").forEach(function (btn) {
          var isActive = btn.dataset.tab === name;
          btn.classList.toggle("active", isActive);
          btn.setAttribute("aria-selected", isActive ? "true" : "false");
        });
        document.querySelectorAll(".tab-panel").forEach(function (panel) {
          panel.classList.toggle("active", panel.id === "tab-" + name);
        });
        // só carrega os iframes da aba que o cliente realmente abriu
        var panel = document.getElementById("tab-" + name);
        if (panel) {
          panel.querySelectorAll("iframe[data-src]").forEach(function (frame) {
            frame.src = frame.dataset.src;
            frame.removeAttribute("data-src");
          });
        }
      }

      document.querySelectorAll("nav.tabs button").forEach(function (btn) {
        btn.addEventListener("click", function () { activateTab(btn.dataset.tab); });
      });

      activateTab("overview");
    })();

    // Aba "Relatório" -- botão de disparo manual + histórico de envios.
    // As duas URLs abaixo são webhooks do n8n (não expõem nenhuma credencial;
    // a API key real do n8n nunca sai do servidor, ver
    // templates/n8n-workflows/report-history-api.json).
    (function () {
      var GENERATE_URL = "{{REPORT_GENERATE_URL}}";
      var HISTORY_URL = "{{REPORT_HISTORY_URL}}";
      var historyLoaded = false;

      function statusEl() { return document.getElementById("report-status"); }

      function showStatus(kind, text) {
        var el = statusEl();
        if (!el) return;
        el.hidden = false;
        el.className = "report-status " + kind;
        el.textContent = text;
      }

      function renderHistory(items) {
        var list = document.getElementById("report-history-list");
        if (!list) return;
        if (!items || !items.length) {
          list.innerHTML = '<div class="empty-tab">Nenhum relatório enviado ainda.</div>';
          return;
        }
        list.innerHTML = items.map(function (item) {
          var cls = item.ok ? "ok" : "bad";
          return '<div class="report-history-row">' +
            '<span class="when">' + item.date + '<small>' + item.time + '</small></span>' +
            '<span class="report-history-status ' + cls + '">' + item.status + '</span>' +
            '</div>';
        }).join("");
      }

      function loadHistory() {
        if (historyLoaded || !HISTORY_URL) return;
        historyLoaded = true;
        fetch(HISTORY_URL)
          .then(function (r) { return r.json(); })
          .then(function (data) { renderHistory(data.items); })
          .catch(function () {
            var list = document.getElementById("report-history-list");
            if (list) list.innerHTML = '<div class="empty-tab">Não foi possível carregar o histórico agora.</div>';
          });
      }

      var btn = document.getElementById("btn-generate-report");
      if (btn) {
        btn.addEventListener("click", function () {
          btn.disabled = true;
          btn.textContent = "Gerando...";
          fetch(GENERATE_URL)
            .then(function () {
              showStatus("ok", "Relatório disparado! Ele chega por e-mail em alguns instantes.");
              historyLoaded = false;
              setTimeout(loadHistory, 4000);
            })
            .catch(function () {
              showStatus("err", "Não foi possível disparar o relatório agora. Tente novamente em instantes.");
            })
            .finally(function () {
              btn.disabled = false;
              btn.textContent = "Gerar relatório agora";
            });
        });
      }

      var reportTabBtn = document.querySelector('nav.tabs button[data-tab="report"]');
      if (reportTabBtn) {
        reportTabBtn.addEventListener("click", loadHistory);
      }
    })();
  </script>
</body>
</html>
