#!/bin/bash
# modules/client-dashboard/new-client.sh
#
# Script de REPLICAÇÃO do dashboard premium por cliente. É o coração deste módulo:
# cada vez que a Arcus Cloud Security fecha um novo cliente, este script provisiona
# um dashboard branded em minutos, sem subir uma nova stack de observabilidade.
#
# --------------------------------------------------------------------------------
# DECISÃO DE ARQUITETURA (leia antes de mexer neste arquivo):
#
# O Grafana OSS (gratuito, é o que usamos no módulo `observability`) NÃO tem
# White-Label / branding por organização — trocar logo, cores e esconder a marca
# "Grafana" é um recurso do Grafana ENTERPRISE (pago, licenciado por instância).
# Rodar um Grafana Enterprise (ou até um OSS completo) por cliente seria caro
# (licença + recursos de servidor) e um pesadelo de manter (patch, updates,
# backup, credenciais duplicadas por cliente).
#
# Por isso a arquitetura adotada é:
#   1) UM ÚNICO Grafana compartilhado (módulo `observability`), com uma
#      Organization própria por cliente — a API de Orgs do Grafana já garante
#      isolamento de dashboards/dados/permissões entre organizations, sem custo
#      de licença. Cada cliente só enxerga a própria org.
#   2) O "premium"/branding de fato (logo do cliente, cor de destaque, domínio
#      próprio tipo dashboard.clientex.com.br) é resolvido com um WRAPPER
#      estático: uma página HTML/CSS simples (sem framework, sem build step)
#      que veste a marca do cliente e embute os painéis do Grafana via
#      <iframe>, usando o recurso "public dashboards" do Grafana (painel
#      somente-leitura, sem exigir login do cliente final).
#   3) Cada cliente = 1 subdomínio próprio, roteado pelo Traefik (HTTPS
#      automático via Let's Encrypt) para um container nginx:alpine que só
#      serve esse HTML estático. Isso é barato (poucos MB de RAM por cliente)
#      e escala horizontalmente sem tocar no Grafana compartilhado.
#
# Trade-off assumido: os painéis embutidos via "public dashboard" ficam
# acessíveis a quem tiver a URL (sem exigir login). Isso é aceitável APENAS
# porque o dashboard copiado é travado (allowlist + templating removido +
# "$client" substituído pelo slug fixo, ver passo 3 abaixo) para mostrar só os
# dados DESTE cliente — nunca copie/publique um dashboard sem essa filtragem.
# Se o cliente exigir controle de acesso forte, a evolução natural é trocar o
# iframe público por embedding autenticado (token de viewer com expiração
# curta, renovado por um backend) ou avaliar Grafana Enterprise White-Labeling
# caso o cliente pague por isso.
# --------------------------------------------------------------------------------
#
# Uso (modo não interativo, pensado para automação/CI):
#   bash new-client.sh <slug-cliente> <dominio-cliente> <cor-hex> <url-logo> [nome-cliente]
#
# Exemplo:
#   bash new-client.sh clientex dashboard.clientex.com.br "#0EA5E9" \
#     https://clientex.com.br/logo.png "Cliente Exemplo Ltda"
#
# Idempotente: reexecutar com o mesmo <slug-cliente> NÃO duplica a Organization
# nem o usuário no Grafana — apenas atualiza o wrapper/branding e reimplanta o
# container estático.

set -Eeuo pipefail

SP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SP_ROOT}/core/common.sh"
source "${SP_ROOT}/core/docker.sh"
source "${SP_ROOT}/core/proxy.sh"

MODULE_SLUG="client-dashboard"
MODULE_DIR="${SP_MODULES_DIR}/${MODULE_SLUG}"

# ------------------------------------------------------------------ argumentos
CLIENT_SLUG="${1:-}"
CLIENT_DOMAIN="${2:-}"
CLIENT_PRIMARY_COLOR="${3:-}"
CLIENT_LOGO_URL="${4:-}"
CLIENT_NAME="${5:-$CLIENT_SLUG}"

if [[ -z "$CLIENT_SLUG" || -z "$CLIENT_DOMAIN" || -z "$CLIENT_PRIMARY_COLOR" || -z "$CLIENT_LOGO_URL" ]]; then
  sp::err "Uso: bash new-client.sh <slug-cliente> <dominio-cliente> <cor-hex> <url-logo> [nome-cliente]"
  exit 1
fi

if ! [[ "$CLIENT_SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  sp::err "slug-cliente inválido: '${CLIENT_SLUG}' (use apenas a-z, 0-9 e hífen)."
  exit 1
fi

if ! [[ "$CLIENT_PRIMARY_COLOR" =~ ^#[0-9a-fA-F]{6}$ ]]; then
  sp::err "cor-hex inválida: '${CLIENT_PRIMARY_COLOR}' (formato esperado: #RRGGBB)."
  exit 1
fi

for cmd in curl jq; do
  sp::has_cmd "$cmd" || { sp::err "Comando obrigatório ausente: ${cmd}"; exit 1; }
done

# ------------------------------------------------------------- pré-requisitos
sp::proxy::ensure_traefik
if ! sp::is_stack_up observability; then
  sp::err "Módulo 'observability' não está rodando. Instale-o antes (ele provê o Grafana compartilhado)."
  exit 1
fi

OBS_ENV="${SP_MODULES_DIR}/observability/.env"
if [[ ! -f "$OBS_ENV" ]]; then
  sp::err "Arquivo ${OBS_ENV} não encontrado. Instale o módulo observability primeiro."
  exit 1
fi
# shellcheck disable=SC1090
set -a; source "$OBS_ENV"; set +a

GRAFANA_BASE_URL="${GRAFANA_BASE_URL:?GRAFANA_BASE_URL ausente em modules/observability/.env}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:?GRAFANA_ADMIN_PASSWORD ausente em modules/observability/.env}"

CLIENT_DIR="${MODULE_DIR}/clients/${CLIENT_SLUG}"
mkdir -p "$CLIENT_DIR"

# ---------------------------------------------------------------- helpers API
# Todas as chamadas administrativas usam Basic Auth do admin do Grafana
# compartilhado. Nunca embutir a senha em log; sp::log só grava o comando/rota.
sp::cd::grafana_admin_api() {
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
      -H "Content-Type: application/json" -X "$method" \
      -d "$data" "${GRAFANA_BASE_URL}${path}"
  else
    curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
      -X "$method" "${GRAFANA_BASE_URL}${path}"
  fi
}

# Idêntica à anterior, mas atuando no contexto de uma org específica (via
# header X-Grafana-Org-Id) — usado para copiar dashboards para a org do cliente
# sem precisar logar como o usuário do cliente.
sp::cd::grafana_admin_api_org() {
  local org_id="$1" method="$2" path="$3" data="${4:-}"
  if [[ -n "$data" ]]; then
    curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
      -H "Content-Type: application/json" -H "X-Grafana-Org-Id: ${org_id}" \
      -X "$method" -d "$data" "${GRAFANA_BASE_URL}${path}"
  else
    curl -fsS -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
      -H "X-Grafana-Org-Id: ${org_id}" -X "$method" "${GRAFANA_BASE_URL}${path}"
  fi
}

# ------------------------------------------------------- 1) Organization
ORG_NAME="Cliente: ${CLIENT_NAME}"

sp::info "Verificando se já existe Organization '${ORG_NAME}' no Grafana..."
EXISTING_ORG_JSON="$(sp::cd::grafana_admin_api GET "/api/orgs/name/$(jq -rn --arg n "$ORG_NAME" '$n|@uri')" || true)"
ORG_ID="$(echo "${EXISTING_ORG_JSON:-{}}" | jq -r '.id // empty')"

if [[ -n "$ORG_ID" ]]; then
  sp::ok "Organization já existe (id=${ORG_ID}). Reaproveitando (idempotente)."
else
  sp::info "Criando Organization '${ORG_NAME}'..."
  CREATE_ORG_JSON="$(sp::cd::grafana_admin_api POST "/api/orgs" "$(jq -n --arg name "$ORG_NAME" '{name:$name}')")"
  ORG_ID="$(echo "$CREATE_ORG_JSON" | jq -r '.orgId // .id')"
  sp::ok "Organization criada (id=${ORG_ID})."
fi

# ------------------------------------------------------- 2) Usuário viewer
VIEWER_LOGIN="cliente-${CLIENT_SLUG}"
VIEWER_EMAIL="${VIEWER_LOGIN}@dashboards.arcuscloud.com.br"

sp::info "Verificando se o usuário '${VIEWER_LOGIN}' já existe..."
LOOKUP_JSON="$(sp::cd::grafana_admin_api GET "/api/users/lookup?loginOrEmail=${VIEWER_LOGIN}" || true)"
VIEWER_USER_ID="$(echo "${LOOKUP_JSON:-{}}" | jq -r '.id // empty')"

# Reaproveita a senha se o cliente já tiver .env (idempotência real: não gera
# senha nova a cada execução, senão invalidaria acessos já distribuídos).
if [[ -f "${CLIENT_DIR}/.env" ]]; then
  # shellcheck disable=SC1091
  set -a; source "${CLIENT_DIR}/.env"; set +a
fi
VIEWER_PASSWORD="${CLIENT_GRAFANA_VIEWER_PASSWORD:-$(sp::gen_password 24)}"

if [[ -n "$VIEWER_USER_ID" ]]; then
  sp::ok "Usuário '${VIEWER_LOGIN}' já existe (id=${VIEWER_USER_ID}). Reaproveitando."
else
  sp::info "Criando usuário viewer '${VIEWER_LOGIN}'..."
  CREATE_USER_JSON="$(sp::cd::grafana_admin_api POST "/api/admin/users" "$(jq -n \
    --arg name "$CLIENT_NAME" --arg login "$VIEWER_LOGIN" --arg email "$VIEWER_EMAIL" \
    --arg password "$VIEWER_PASSWORD" \
    '{name:$name, login:$login, email:$email, password:$password}')")"
  VIEWER_USER_ID="$(echo "$CREATE_USER_JSON" | jq -r '.id')"
  sp::ok "Usuário criado (id=${VIEWER_USER_ID})."
fi

# Garante papel Viewer na org do cliente (idempotente: ignora erro se já membro)
sp::cd::grafana_admin_api_org "$ORG_ID" POST "/api/org/users" \
  "$(jq -n --arg loginOrEmail "$VIEWER_LOGIN" '{loginOrEmail:$loginOrEmail, role:"Viewer"}')" \
  >/dev/null 2>&1 || sp::warn "Usuário já era membro da org (ou role já atribuída) — seguindo."

# ------------------------------------------------- 3) Copiar dashboards padrão
# ATENÇÃO — achado C2 da auditoria de segurança (não reverta sem entender):
# Antes, este loop buscava TODOS os dashboards da org 1 via /api/search e
# publicava cada um como public-dashboard. Dois problemas graves:
#   1) Copiava também dashboards internos (ex: docker-overview.json, que mostra
#      logs/métricas do SERVIDOR CENTRAL da Arcus, não do cliente) para a org
#      do cliente e os publicava na internet sem login.
#   2) O dashboard "remote-clients.json" tem uma variável $client com
#      includeAll=true e valor salvo "All" — public dashboards não deixam o
#      visitante trocar a variável, então o link público de QUALQUER cliente
#      mostrava métricas E LOGS de TODOS os clientes.
# Fix: (a) allowlist explícita de UIDs publicáveis (nunca mais um `search`
# cego); (b) remove a seção `templating` e substitui todo "$client" literal
# pelo slug fixo deste cliente antes de salvar — assim o dashboard copiado
# fica estruturalmente preso a UM cliente, não importa o que o Grafana ou o
# visitante tentem fazer com a URL pública.
PUBLISHABLE_DASHBOARD_UIDS=("remote-clients")

sp::info "Copiando dashboards padrão (allowlist) para a org do cliente..."
PANEL_URLS=()

for uid in "${PUBLISHABLE_DASHBOARD_UIDS[@]}"; do
  DASH_JSON="$(sp::cd::grafana_admin_api_org 1 GET "/api/dashboards/uid/${uid}" || true)"
  if [[ -z "$DASH_JSON" ]] || [[ "$(echo "$DASH_JSON" | jq -r '.dashboard // empty')" == "" ]]; then
    sp::warn "Dashboard '${uid}' não encontrado na org principal — pulando (instale/atualize o observability primeiro)."
    continue
  fi
  DASH_TITLE="$(echo "$DASH_JSON" | jq -r '.dashboard.title')"

  # Remove id/uid (recriação sem conflito), zera templating (o visitante do
  # link público não pode trocar variável) e substitui "$client" literal pelo
  # slug fixo deste cliente em qualquer string do dashboard (título, expr,
  # legendFormat, etc) — isso é o que impede o link público de um cliente
  # mostrar dados de outro.
  NEW_DASH_PAYLOAD="$(echo "$DASH_JSON" | jq --arg slug "$CLIENT_SLUG" '
    .dashboard.id = null |
    .dashboard.uid = null |
    .dashboard.templating = {list: []} |
    .dashboard |= walk(if type == "string" then gsub("\\$client"; $slug) else . end) |
    {dashboard: .dashboard, overwrite: true, message: "replicado por new-client.sh (filtrado para \($slug))"}
  ')"

  IMPORT_RESULT="$(sp::cd::grafana_admin_api_org "$ORG_ID" POST "/api/dashboards/db" "$NEW_DASH_PAYLOAD")"
  NEW_UID="$(echo "$IMPORT_RESULT" | jq -r '.uid')"
  sp::ok "Dashboard '${DASH_TITLE}' copiado e filtrado para client='${CLIENT_SLUG}' (uid=${NEW_UID})."

  # Habilita "public dashboard" (somente leitura, sem login) para permitir o
  # embed via iframe no wrapper estático — seguro agora que o dashboard está
  # travado no slug deste cliente (ver decisão de arquitetura no topo).
  PUBLIC_RESULT="$(sp::cd::grafana_admin_api_org "$ORG_ID" POST \
    "/api/dashboards/uid/${NEW_UID}/public-dashboards" \
    '{"isEnabled": true, "share": "public"}' || true)"
  PUBLIC_UID="$(echo "${PUBLIC_RESULT:-{}}" | jq -r '.accessToken // .uid // empty')"

  if [[ -n "$PUBLIC_UID" ]]; then
    PANEL_URLS+=("${GRAFANA_BASE_URL}/public-dashboards/${PUBLIC_UID}")
  else
    sp::warn "Não foi possível habilitar public-dashboard para '${DASH_TITLE}' (recurso pode não estar habilitado no Grafana). Pulei o iframe."
  fi
done

if [[ "${#PANEL_URLS[@]}" -eq 0 ]]; then
  sp::warn "Nenhum painel público disponível ainda — o wrapper será gerado sem iframes. Rode novamente após publicar dashboards na org principal do Grafana."
fi

# ------------------------------------------------------- 4) Persistir .env do cliente
{
  echo "CLIENT_NAME=${CLIENT_NAME}"
  echo "CLIENT_DOMAIN=${CLIENT_DOMAIN}"
  echo "CLIENT_PRIMARY_COLOR=${CLIENT_PRIMARY_COLOR}"
  echo "CLIENT_LOGO_URL=${CLIENT_LOGO_URL}"
  echo "GRAFANA_BASE_URL=${GRAFANA_BASE_URL}"
  echo "CLIENT_GRAFANA_ORG_ID=${ORG_ID}"
  echo "CLIENT_GRAFANA_VIEWER_USER=${VIEWER_LOGIN}"
  echo "CLIENT_GRAFANA_VIEWER_PASSWORD=${VIEWER_PASSWORD}"
} > "${CLIENT_DIR}/.env"
chmod 600 "${CLIENT_DIR}/.env"
sp::ok "Credenciais do cliente salvas em ${CLIENT_DIR}/.env"

# ------------------------------------------------------- 5) Gerar wrapper HTML
IFRAMES_HTML=""
for url in "${PANEL_URLS[@]+"${PANEL_URLS[@]}"}"; do
  IFRAMES_HTML+="      <div class=\"panel-card\"><iframe src=\"${url}\" loading=\"lazy\"></iframe></div>"$'\n'
done

DATA_DIR="$(sp::ensure_data_dir "client-dashboard/${CLIENT_SLUG}")"
mkdir -p "${DATA_DIR}/html"

# sed com delimitador alternativo (|) porque URLs contêm '/'
sed \
  -e "s|{{CLIENT_NAME}}|${CLIENT_NAME}|g" \
  -e "s|{{CLIENT_LOGO_URL}}|${CLIENT_LOGO_URL}|g" \
  -e "s|{{CLIENT_PRIMARY_COLOR}}|${CLIENT_PRIMARY_COLOR}|g" \
  -e "s|{{CLIENT_DOMAIN}}|${CLIENT_DOMAIN}|g" \
  "${SP_TEMPLATES_DIR}/client-dashboard/wrapper.html.tpl" \
  | awk -v iframes="$IFRAMES_HTML" '{gsub(/{{GRAFANA_PANEL_IFRAMES}}/, iframes); print}' \
  > "${DATA_DIR}/html/index.html"

sp::ok "Wrapper HTML gerado em ${DATA_DIR}/html/index.html"

# ------------------------------------------------- 6) Gerar e implantar compose
COMPOSE_FILE="${CLIENT_DIR}/docker-compose.yml"
sed \
  -e "s|{{CLIENT_SLUG}}|${CLIENT_SLUG}|g" \
  -e "s|{{CLIENT_DOMAIN}}|${CLIENT_DOMAIN}|g" \
  "${SP_TEMPLATES_DIR}/client-dashboard/docker-compose.yml.tpl" \
  > "$COMPOSE_FILE"

sp::docker::ensure_network rede_publica
STACK_NAME="clientdash-${CLIENT_SLUG}"
sp::docker::deploy_stack "$STACK_NAME" "$COMPOSE_FILE"

# ------------------------------------------------------------- 7) Validação
sp::info "Aguardando emissão do certificado SSL (Let's Encrypt) e propagação..."
sleep 5
if curl -ksS -o /dev/null -w '%{http_code}' "https://${CLIENT_DOMAIN}" | grep -qE '^(200|301|302)$'; then
  sp::ok "Dashboard do cliente '${CLIENT_NAME}' respondendo em https://${CLIENT_DOMAIN}"
else
  sp::warn "https://${CLIENT_DOMAIN} ainda não respondeu 200/301/302. Confira o DNS (registro A) e aguarde o Traefik emitir o certificado."
fi

sp::log "NEW_CLIENT" "$MODULE_SLUG" "slug=${CLIENT_SLUG} domain=${CLIENT_DOMAIN} org_id=${ORG_ID} stack=${STACK_NAME}"
sp::ok "Provisionamento concluído para '${CLIENT_NAME}'."
