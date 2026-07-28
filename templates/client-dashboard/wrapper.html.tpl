<!-- templates/client-dashboard/wrapper.html.tpl
     Shell estático "premium" com a marca do cliente, sem framework/build step.
     Variáveis substituídas por new-client.sh (sed):
       {{CLIENT_NAME}}          - nome do cliente (título/alt do logo)
       {{CLIENT_LOGO_URL}}      - URL pública do logo do cliente
       {{CLIENT_PRIMARY_COLOR}} - cor de destaque em hex (ex: #0EA5E9)
       {{CLIENT_DOMAIN}}        - domínio final (usado no rodapé/meta)
       {{GRAFANA_PANEL_IFRAMES}}- bloco HTML já pronto com um <div class="panel-card">
                                  por painel, com título + iframe (gerado
                                  dinamicamente por new-client.sh) -->
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
    padding: 16px 32px;
    background: color-mix(in srgb, var(--bg-header) 88%, transparent);
    backdrop-filter: blur(10px);
    border-bottom: 1px solid var(--border-color);
    position: sticky;
    top: 0;
    z-index: 10;
  }

  header::after {
    content: "";
    position: absolute;
    left: 0; right: 0; bottom: -1px;
    height: 2px;
    background: linear-gradient(90deg, var(--client-primary), transparent 70%);
  }

  header img {
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

  .status-badge {
    margin-left: auto;
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

  main {
    padding: 28px 32px 56px;
    max-width: 1600px;
    margin: 0 auto;
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
    height: 360px;
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
    main { padding: 16px; }
    .panels-grid { grid-template-columns: 1fr; }
    .panel-card-body { height: 300px; }
  }
</style>
</head>
<body>
  <header>
    <img src="{{CLIENT_LOGO_URL}}" alt="{{CLIENT_NAME}}">
    <h1>{{CLIENT_NAME}}<small>Painel de monitoramento</small></h1>
    <span class="status-badge"><span class="status-dot"></span>Operacional</span>
  </header>

  <main>
    <div class="panels-grid">
      {{GRAFANA_PANEL_IFRAMES}}
    </div>
  </main>

  <footer>
    Powered by Arcus Cloud Security &middot; <a href="https://{{CLIENT_DOMAIN}}">{{CLIENT_DOMAIN}}</a>
  </footer>
</body>
</html>
