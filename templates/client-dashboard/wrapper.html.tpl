<!-- templates/client-dashboard/wrapper.html.tpl
     Shell estático "premium" com a marca do cliente, sem framework/build step.
     Variáveis substituídas por new-client.sh (sed):
       {{CLIENT_NAME}}          - nome do cliente (título/alt do logo)
       {{CLIENT_LOGO_URL}}      - URL pública do logo do cliente
       {{CLIENT_PRIMARY_COLOR}} - cor de destaque em hex (ex: #0EA5E9)
       {{CLIENT_DOMAIN}}        - domínio final (usado no rodapé/meta)
       {{GRAFANA_PANEL_IFRAMES}}- bloco HTML já pronto com um <iframe> por painel
                                  (gerado dinamicamente por new-client.sh a partir
                                  da lista de URLs de embed/public-dashboard) -->
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
    --bg-base: #0b0e14;
    --bg-panel: #12161f;
    --bg-header: #0d1017;
    --border-color: #232838;
    --text-main: #e6e8ec;
    --text-muted: #8b93a7;
  }

  * { box-sizing: border-box; }

  body {
    margin: 0;
    background: var(--bg-base);
    color: var(--text-main);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  }

  header {
    display: flex;
    align-items: center;
    gap: 16px;
    padding: 16px 32px;
    background: var(--bg-header);
    border-bottom: 2px solid var(--client-primary);
    position: sticky;
    top: 0;
    z-index: 10;
  }

  header img {
    height: 36px;
    width: auto;
    object-fit: contain;
  }

  header h1 {
    font-size: 18px;
    font-weight: 600;
    margin: 0;
    color: var(--text-main);
  }

  header .badge {
    margin-left: auto;
    font-size: 12px;
    color: var(--text-muted);
    border: 1px solid var(--border-color);
    border-radius: 999px;
    padding: 4px 12px;
  }

  main {
    padding: 24px 32px 48px;
  }

  .panels-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(420px, 1fr));
    gap: 20px;
  }

  .panel-card {
    background: var(--bg-panel);
    border: 1px solid var(--border-color);
    border-radius: 10px;
    overflow: hidden;
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.35);
  }

  .panel-card iframe {
    width: 100%;
    height: 360px;
    border: 0;
    display: block;
    background: var(--bg-panel);
  }

  footer {
    text-align: center;
    padding: 24px;
    color: var(--text-muted);
    font-size: 12px;
  }

  footer a {
    color: var(--client-primary);
    text-decoration: none;
  }

  @media (max-width: 640px) {
    header { padding: 12px 16px; }
    main { padding: 16px; }
    .panels-grid { grid-template-columns: 1fr; }
  }
</style>
</head>
<body>
  <header>
    <img src="{{CLIENT_LOGO_URL}}" alt="{{CLIENT_NAME}}">
    <h1>{{CLIENT_NAME}} — Painel de Monitoramento</h1>
    <span class="badge">tempo real</span>
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
