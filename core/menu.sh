#!/bin/bash
# core/menu.sh — geração do menu a partir dos manifests em config/tools/*.yaml
# Separação estrita: este arquivo só cuida de apresentação. Lógica de negócio fica
# nos módulos (modules/<slug>/*.sh) e no core/docker.sh, core/proxy.sh etc.
set -Eeuo pipefail

# Banner ASCII art principal — "ARCUS" em bloco (estilo ANSI Shadow), fixo/hardcoded
# (mesma ideia visual do SetupOrion: arte grande + subtítulo, sem depender de figlet)
sp::menu::banner() {
  echo -e "${C_CYAN}${C_BOLD}"
  echo -e ' █████╗  ██████╗   ██████╗██╗   ██╗███████╗'
  echo -e '██╔══██╗ ██╔══██╗ ██╔════╝██║   ██║██╔════╝'
  echo -e '███████║ ██████╔╝ ██║     ██║   ██║███████╗'
  echo -e '██╔══██║ ██╔══██╗ ██║     ██║   ██║╚════██║'
  echo -e '██║  ██║ ██║  ██║ ╚██████╗╚██████╔╝███████║'
  echo -e '╚═╝  ╚═╝ ╚═╝  ╚═╝  ╚═════╝ ╚═════╝ ╚══════╝'
  echo -e "${C_RESET}"
}

# Cabeçalho principal (usado só na tela raiz do menu)
sp::menu::header() {
  clear
  sp::menu::banner
  echo -e "${C_YELLOW}════════════════════════════════════════════════════════════${C_RESET}"
  echo -e "${C_WHITE}${C_BOLD}   CLOUD SECURITY  ·  SETUP-PLATFORM${C_RESET}"
  echo -e "${C_YELLOW}════════════════════════════════════════════════════════════${C_RESET}"
}

# Mini cabeçalho para telas internas (categorias, ferramentas, ações, AWS)
# Uso: sp::menu::section_header "Texto do título"
sp::menu::section_header() {
  local title="$1"
  clear
  sp::menu::banner
  echo -e "${C_YELLOW}────────────────────────────────────────────────────────────${C_RESET}"
  echo -e "${C_WHITE}${C_BOLD}   ${title}${C_RESET}"
  echo -e "${C_YELLOW}────────────────────────────────────────────────────────────${C_RESET}"
  echo ""
}

# Lista categorias distintas presentes em config/tools/*.yaml
sp::menu::categories() {
  yq eval '.category' "${SP_CONFIG_DIR}"/tools/*.yaml 2>/dev/null | sort -u
}

# Lista ferramentas (slug + name) de uma categoria
sp::menu::tools_in_category() {
  local category="$1" f slug name
  for f in "${SP_CONFIG_DIR}"/tools/*.yaml; do
    [[ -e "$f" ]] || continue
    if [[ "$(sp::yaml_get "$f" '.category')" == "$category" ]]; then
      slug="$(sp::yaml_get "$f" '.slug')"
      name="$(sp::yaml_get "$f" '.name')"
      echo "${slug}|${name}"
    fi
  done
}

sp::menu::main() {
  while true; do
    sp::menu::header
    echo ""
    echo -e " ${C_CYAN}1)${C_RESET} Instalação base do servidor"
    echo -e " ${C_CYAN}2)${C_RESET} Configurar proxy reverso (Traefik) e SSL"
    echo -e " ${C_CYAN}3)${C_RESET} Ferramentas por categoria"
    echo -e " ${C_CYAN}4)${C_RESET} Atualizações"
    echo -e " ${C_CYAN}5)${C_RESET} Backups"
    echo -e " ${C_CYAN}6)${C_RESET} Restauração"
    echo -e " ${C_CYAN}7)${C_RESET} Diagnóstico"
    echo -e " ${C_CYAN}8)${C_RESET} Remoção de ferramentas"
    echo -e " ${C_CYAN}9)${C_RESET} Configurações AWS"
    echo -e " ${C_RED}0)${C_RESET} Sair"
    echo ""
    echo -e "${C_YELLOW}────────────────────────────────────────────────────────────${C_RESET}"
    read -r -p "$(echo -e "${C_WHITE}Escolha uma opção: ${C_RESET}")" opt
    case "$opt" in
      1) sp::os::install_base_deps; sp::os::setup_firewall; sp::docker::install
         sp::aws::is_ec2 && sp::aws::advise ;;
      2) sp::proxy::ensure_traefik ;;
      3) sp::menu::category_menu ;;
      4) sp::menu::update_menu ;;
      5) sp::menu::backup_menu ;;
      6) sp::menu::restore_menu ;;
      7) sp::validate::all ;;
      8) sp::menu::uninstall_menu ;;
      9) sp::menu::aws_menu ;;
      0) echo -e "${C_GREEN}Até mais!${C_RESET}"; exit 0 ;;
      *) sp::warn "Opção inválida." ;;
    esac
    read -r -p "Pressione ENTER para continuar..." _
  done
}

sp::menu::category_menu() {
  local categories=() i=1 choice
  mapfile -t categories < <(sp::menu::categories)

  sp::menu::section_header "CATEGORIAS DISPONÍVEIS"
  for c in "${categories[@]}"; do
    echo -e " ${C_CYAN}${i})${C_RESET} ${c}"
    ((i++))
  done
  echo -e " ${C_RED}0)${C_RESET} Voltar"
  echo ""
  read -r -p "$(echo -e "${C_WHITE}Categoria: ${C_RESET}")" choice
  [[ "$choice" == "0" ]] && return
  local selected="${categories[$((choice-1))]}"
  sp::menu::tool_menu "$selected"
}

sp::menu::tool_menu() {
  local category="$1"
  local tools=() i=1 choice slug name
  mapfile -t tools < <(sp::menu::tools_in_category "$category")

  sp::menu::section_header "FERRAMENTAS — ${category}"
  for t in "${tools[@]}"; do
    IFS='|' read -r slug name <<< "$t"
    echo -e " ${C_CYAN}${i})${C_RESET} ${name} ${C_DIM}(${slug})${C_RESET}"
    ((i++))
  done
  echo -e " ${C_RED}0)${C_RESET} Voltar"
  echo ""
  read -r -p "$(echo -e "${C_WHITE}Ferramenta: ${C_RESET}")" choice
  [[ "$choice" == "0" ]] && return
  IFS='|' read -r slug name <<< "${tools[$((choice-1))]}"
  sp::menu::tool_actions "$slug"
}

sp::menu::tool_actions() {
  local slug="$1" choice
  sp::menu::section_header "AÇÕES — ${slug}"
  echo -e " ${C_CYAN}1)${C_RESET} Instalar"
  echo -e " ${C_CYAN}2)${C_RESET} Atualizar"
  echo -e " ${C_CYAN}3)${C_RESET} Remover"
  echo -e " ${C_CYAN}4)${C_RESET} Validar"
  echo -e " ${C_CYAN}5)${C_RESET} Ver logs"
  echo -e " ${C_RED}0)${C_RESET} Voltar"
  echo ""
  read -r -p "$(echo -e "${C_WHITE}Ação: ${C_RESET}")" choice
  local module_dir="${SP_MODULES_DIR}/${slug}"
  case "$choice" in
    1) bash "${module_dir}/install.sh" ;;
    2) bash "${module_dir}/install.sh" --update ;;
    3) bash "${module_dir}/uninstall.sh" ;;
    4) sp::validate::tool "$slug" ;;
    5) sp::logs::tail_tool "$slug" ;;
    0) return ;;
  esac
}

sp::menu::aws_menu() {
  sp::menu::section_header "CONFIGURAÇÕES AWS"
  echo -e " ${C_CYAN}1)${C_RESET} Detectar ambiente / mostrar metadados"
  echo -e " ${C_CYAN}2)${C_RESET} Associar Elastic IP (instruções)"
  echo -e " ${C_CYAN}3)${C_RESET} Rodar diagnóstico de Security Group"
  echo -e " ${C_RED}0)${C_RESET} Voltar"
  echo ""
  read -r -p "$(echo -e "${C_WHITE}Opção: ${C_RESET}")" choice
  case "$choice" in
    1) sp::aws::advise ;;
    2) sp::info "Console: EC2 > Elastic IPs > Allocate > Associate com esta instância." ;;
    3) bash "${SP_PROVIDERS_DIR}/aws/sg-check.sh" 2>/dev/null || sp::warn "sg-check.sh ainda não implementado." ;;
    0) return ;;
  esac
}

sp::menu::update_menu()    { sp::menu::category_menu; }
sp::menu::backup_menu()    { sp::info "Rode: modules/<slug>/backup.sh (a definir por módulo)."; }
sp::menu::restore_menu()   { sp::info "Rode: modules/<slug>/restore.sh (a definir por módulo)."; }
sp::menu::uninstall_menu() { sp::menu::category_menu; }
