#!/bin/bash

# Script de instalação e configuração
# Docker + Traefik 2.11.3 + Portainer

set -e

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funções auxiliares
print_header() {
    echo -e "\n${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Verificar se está rodando como root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        print_warning "Você está executando como root. Isso não é recomendado."
        print_info "Prefira executar como usuário normal com acesso ao Docker"
        echo
    fi
}

# Verificar pré-requisitos
check_prerequisites() {
    print_header "Verificando Pré-requisitos"

    local errors=0

    # Verificar Docker
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | cut -d ' ' -f3 | cut -d ',' -f1)
        print_success "Docker instalado (versão $DOCKER_VERSION)"

        # Verificar se o usuário pode executar docker
        if docker ps &> /dev/null; then
            print_success "Permissões Docker OK"
        else
            print_error "Usuário não tem permissão para executar Docker"
            print_info "Execute: sudo usermod -aG docker \$USER && newgrp docker"
            errors=$((errors + 1))
        fi
    else
        print_error "Docker não está instalado"
        print_info "Visite: https://docs.docker.com/engine/install/"
        errors=$((errors + 1))
    fi

    # Verificar Docker Compose
    if command -v docker-compose &> /dev/null; then
        COMPOSE_VERSION=$(docker-compose --version | cut -d ' ' -f4 | cut -d ',' -f1)
        print_success "Docker Compose instalado (versão $COMPOSE_VERSION)"
    elif docker compose version &> /dev/null; then
        COMPOSE_VERSION=$(docker compose version --short)
        print_success "Docker Compose Plugin instalado (versão $COMPOSE_VERSION)"
    else
        print_error "Docker Compose não está instalado"
        print_info "Visite: https://docs.docker.com/compose/install/"
        errors=$((errors + 1))
    fi

    # Verificar portas
    print_info "Verificando portas necessárias..."
    for port in 80 443 8080; do
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            print_warning "Porta $port já está em uso"
            print_info "Processo: $(lsof -Pi :$port -sTCP:LISTEN | tail -n 1)"
        else
            print_success "Porta $port disponível"
        fi
    done

    if [ $errors -gt 0 ]; then
        echo
        print_error "Corrija os erros acima antes de continuar"
        exit 1
    fi
}

# Gerar senha hash para Traefik
generate_password_hash() {
    local username=$1
    local password=$2

    if command -v htpasswd &> /dev/null; then
        echo $(htpasswd -nb "$username" "$password" | sed -e s/\\$/\\$\\$/g)
    else
        print_warning "htpasswd não encontrado, usando senha padrão"
        echo "admin:\$\$apr1\$\$8EVjn/nj\$\$GiLUZqcbueTFeD23SuB6x0"
    fi
}

# Função de limpeza
cleanup_existing() {
    print_header "Limpeza de Containers Existentes"

    echo -e "${YELLOW}Esta opção irá:${NC}"
    echo "  - Parar e remover todos os containers do projeto"
    echo "  - Remover a rede proxy"
    echo "  - Remover volumes (dados persistentes)"
    echo
    read -p "Deseja remover todos os containers e dados do projeto? [s/N]: " CLEANUP

    if [[ "$CLEANUP" =~ ^[Ss]$ ]]; then
        print_info "Parando e removendo containers..."
        docker-compose down -v 2>/dev/null || true

        print_info "Removendo rede proxy..."
        docker network rm proxy 2>/dev/null || true

        print_success "Limpeza concluída!"
        echo
    else
        print_info "Limpeza cancelada"
        echo
    fi
}

# Coletar informações do usuário
collect_information() {
    print_header "Configuração Inicial"

    echo -e "${YELLOW}Escolha o modo de instalação:${NC}"
    echo "1) Desenvolvimento Local (sem domínio/SSL)"
    echo "2) Produção (com domínio e Let's Encrypt)"
    echo
    read -p "Opção [1]: " INSTALL_MODE
    INSTALL_MODE=${INSTALL_MODE:-1}

    echo

    # Domínio
    if [ "$INSTALL_MODE" = "2" ]; then
        read -p "Digite seu domínio (ex: example.com): " DOMAIN
        while [ -z "$DOMAIN" ]; do
            print_error "Domínio é obrigatório para modo produção"
            read -p "Digite seu domínio (ex: example.com): " DOMAIN
        done
    else
        DOMAIN="localhost"
        print_info "Modo desenvolvimento: usando localhost"
    fi

    # Timezone
    echo
    CURRENT_TZ=$(timedatectl 2>/dev/null | grep "Time zone" | awk '{print $3}' || echo "America/Sao_Paulo")
    read -p "Timezone [$CURRENT_TZ]: " TZ
    TZ=${TZ:-$CURRENT_TZ}

    # Credenciais Traefik Dashboard
    echo
    print_info "Configure as credenciais para o Dashboard do Traefik"
    read -p "Usuário [admin]: " TRAEFIK_USERNAME
    TRAEFIK_USERNAME=${TRAEFIK_USERNAME:-admin}

    read -sp "Senha [admin]: " TRAEFIK_PASSWORD
    echo
    TRAEFIK_PASSWORD=${TRAEFIK_PASSWORD:-admin}

    # Gerar hash
    print_info "Gerando hash da senha..."
    TRAEFIK_USER=$(generate_password_hash "$TRAEFIK_USERNAME" "$TRAEFIK_PASSWORD")

    # Subdomínios
    echo
    print_info "Configure os subdomínios para acesso aos serviços"
    echo -e "${YELLOW}Exemplos: pr, traefik, dashboard${NC}"
    read -p "Subdomínio do Traefik [pr]: " SUBDOMAIN_TRAEFIK
    SUBDOMAIN_TRAEFIK=${SUBDOMAIN_TRAEFIK:-pr}

    echo -e "${YELLOW}Exemplos: painel, portainer, admin${NC}"
    read -p "Subdomínio do Portainer [painel]: " SUBDOMAIN_PORTAINER
    SUBDOMAIN_PORTAINER=${SUBDOMAIN_PORTAINER:-painel}

    echo -e "${YELLOW}Exemplos: n8n, automacao, workflows${NC}"
    read -p "Subdomínio do n8n [n8n]: " SUBDOMAIN_N8N
    SUBDOMAIN_N8N=${SUBDOMAIN_N8N:-n8n}

    echo -e "${YELLOW}Exemplos: remotion, video, studio${NC}"
    read -p "Subdomínio do Remotion [remotion]: " SUBDOMAIN_REMOTION
    SUBDOMAIN_REMOTION=${SUBDOMAIN_REMOTION:-remotion}

    # Cloudflare (apenas para produção)
    if [ "$INSTALL_MODE" = "2" ]; then
        echo
        print_info "Para usar Let's Encrypt com Cloudflare, você precisa:"
        print_info "- API Email (email da sua conta Cloudflare)"
        print_info "- API Key ou API Token"
        echo
        read -p "Configurar Cloudflare agora? [s/N]: " SETUP_CF

        if [[ "$SETUP_CF" =~ ^[Ss]$ ]]; then
            read -p "Email Cloudflare: " CF_API_EMAIL
            read -sp "API Key/Token Cloudflare: " CF_API_KEY
            echo
            USE_CLOUDFLARE="true"
        else
            print_warning "Você pode configurar Cloudflare depois editando o arquivo .env"
            CF_API_EMAIL="your-email@example.com"
            CF_API_KEY="your-cloudflare-api-key"
            USE_CLOUDFLARE="false"
        fi
    fi
}

# Criar arquivo .env
create_env_file() {
    print_header "Criando Arquivo de Configuração"

    cat > .env << EOF
# Domain configuration
DOMAIN=$DOMAIN

# Subdomains configuration
SUBDOMAIN_TRAEFIK=$SUBDOMAIN_TRAEFIK
SUBDOMAIN_PORTAINER=$SUBDOMAIN_PORTAINER
SUBDOMAIN_N8N=$SUBDOMAIN_N8N
SUBDOMAIN_REMOTION=$SUBDOMAIN_REMOTION

# Timezone
TZ=$TZ

# Traefik Dashboard Authentication
TRAEFIK_USER=$TRAEFIK_USER
EOF

    # n8n encryption key
    N8N_ENCRYPTION_KEY=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 64)
    cat >> .env << EOF

# n8n Configuration
N8N_PROTOCOL=https
N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY
EOF

    if [ "$INSTALL_MODE" = "2" ]; then
        cat >> .env << EOF

# Cloudflare API (for Let's Encrypt DNS challenge)
CF_API_EMAIL=$CF_API_EMAIL
CF_API_KEY=$CF_API_KEY
EOF
    fi

    print_success "Arquivo .env criado"
}

# Preparar estrutura de diretórios
prepare_directories() {
    print_header "Preparando Estrutura de Diretórios"

    # Criar diretórios se não existirem
    mkdir -p data/traefik data/portainer data/n8n data/remotion/output traefik/dynamic remotion/project
    print_success "Diretórios criados"

    # Criar e configurar acme.json
    if [ ! -f data/traefik/acme.json ]; then
        touch data/traefik/acme.json
        chmod 600 data/traefik/acme.json
        print_success "Arquivo acme.json criado com permissões corretas"
    else
        print_info "Arquivo acme.json já existe"
    fi
}

# Atualizar configuração do Traefik se necessário
update_traefik_config() {
    if [ "$INSTALL_MODE" = "1" ]; then
        print_header "Ajustando Configuração para Desenvolvimento"

        # Criar configuração simplificada para desenvolvimento
        cat > traefik/traefik.yml << EOF
api:
  dashboard: true
  debug: true

entryPoints:
  http:
    address: ":80"
  https:
    address: ":443"

serversTransport:
  insecureSkipVerify: true

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: proxy
  file:
    directory: /dynamic
    watch: true

log:
  level: INFO
EOF
        print_success "Configuração ajustada para modo desenvolvimento"
    else
        # Atualizar email no traefik.yml para produção
        if [ "$USE_CLOUDFLARE" = "true" ]; then
            sed -i "s/your-email@example.com/$CF_API_EMAIL/g" traefik/traefik.yml
            print_success "Email configurado no traefik.yml"
        fi
    fi
}

# Atualizar docker-compose para desenvolvimento
update_docker_compose() {
    if [ "$INSTALL_MODE" = "1" ]; then
        print_header "Ajustando Docker Compose para Desenvolvimento"

        # Remover labels HTTPS do Traefik
        sed -i '/traefik-secure/d' docker-compose.yml
        sed -i '/tls.certresolver/d' docker-compose.yml
        sed -i '/tls.domains/d' docker-compose.yml

        print_success "Docker Compose ajustado para desenvolvimento"
    else
        # Adicionar variáveis de ambiente Cloudflare se configurado
        if [ "$USE_CLOUDFLARE" = "true" ]; then
            # Verificar se já tem as variáveis
            if ! grep -q "CF_API_EMAIL" docker-compose.yml; then
                # Adicionar após a linha de TZ no serviço traefik
                sed -i '/- TZ=/a\      - CF_API_EMAIL=${CF_API_EMAIL}\n      - CF_API_KEY=${CF_API_KEY}' docker-compose.yml
                print_success "Variáveis Cloudflare adicionadas ao docker-compose.yml"
            fi
        fi
    fi
}

# Iniciar serviços
start_services() {
    print_header "Iniciando Serviços"

    print_info "Parando containers existentes (se houver)..."
    docker-compose down 2>/dev/null || true

    print_info "Baixando imagens..."
    docker-compose pull

    print_info "Iniciando containers..."
    docker-compose up -d

    print_success "Serviços iniciados!"
}

# Verificar status dos serviços
check_services() {
    print_header "Verificando Status dos Serviços"

    sleep 5

    echo
    docker-compose ps
    echo

    # Verificar se os containers estão rodando
    if docker-compose ps | grep -q "Up"; then
        print_success "Containers estão rodando"
    else
        print_error "Alguns containers não iniciaram corretamente"
        print_info "Execute: docker-compose logs"
        return 1
    fi
}

# Exibir informações de acesso
show_access_info() {
    print_header "Instalação Concluída!"

    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           ACESSO AOS SERVIÇOS                          ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo

    if [ "$INSTALL_MODE" = "1" ]; then
        echo -e "${BLUE}Traefik Dashboard:${NC}"
        echo -e "  Via proxy: ${YELLOW}http://$SUBDOMAIN_TRAEFIK.$DOMAIN${NC}"
        echo -e "  Direto:    ${YELLOW}http://localhost:8080${NC}"
        echo -e "  Usuário: ${YELLOW}$TRAEFIK_USERNAME${NC}"
        echo -e "  Senha: ${YELLOW}$TRAEFIK_PASSWORD${NC}"
        echo
        echo -e "${BLUE}Portainer:${NC}"
        echo -e "  Via proxy: ${YELLOW}http://$SUBDOMAIN_PORTAINER.$DOMAIN${NC}"
        echo -e "  Direto:    ${YELLOW}http://localhost:9000${NC}"
        echo -e "  ${YELLOW}Configure o usuário admin no primeiro acesso${NC}"
        echo
        echo -e "${BLUE}n8n (Automação de Workflows):${NC}"
        echo -e "  Via proxy: ${YELLOW}http://$SUBDOMAIN_N8N.$DOMAIN${NC}"
        echo -e "  Direto:    ${YELLOW}http://localhost:5678${NC}"
        echo -e "  ${YELLOW}Configure o usuário admin no primeiro acesso${NC}"
        echo
        echo -e "${BLUE}Remotion Studio (Renderização de Vídeo):${NC}"
        echo -e "  Via proxy: ${YELLOW}http://$SUBDOMAIN_REMOTION.$DOMAIN${NC}"
        echo -e "  ${YELLOW}Coloque seu projeto em: ./remotion/project/${NC}"
        echo -e "  ${YELLOW}Vídeos renderizados em: ./data/remotion/output/${NC}"
    else
        echo -e "${BLUE}Traefik Dashboard:${NC}"
        echo -e "  URL: ${YELLOW}https://$SUBDOMAIN_TRAEFIK.$DOMAIN${NC}"
        echo -e "  Usuário: ${YELLOW}$TRAEFIK_USERNAME${NC}"
        echo -e "  Senha: ${YELLOW}$TRAEFIK_PASSWORD${NC}"
        echo
        echo -e "${BLUE}Portainer:${NC}"
        echo -e "  URL: ${YELLOW}https://$SUBDOMAIN_PORTAINER.$DOMAIN${NC}"
        echo -e "  ${YELLOW}Configure o usuário admin no primeiro acesso${NC}"
        echo
        echo -e "${BLUE}n8n (Automação de Workflows):${NC}"
        echo -e "  URL: ${YELLOW}https://$SUBDOMAIN_N8N.$DOMAIN${NC}"
        echo -e "  ${YELLOW}Configure o usuário admin no primeiro acesso${NC}"
        echo
        echo -e "${BLUE}Remotion Studio (Renderização de Vídeo):${NC}"
        echo -e "  URL: ${YELLOW}https://$SUBDOMAIN_REMOTION.$DOMAIN${NC}"
        echo -e "  ${YELLOW}Coloque seu projeto em: ./remotion/project/${NC}"
        echo -e "  ${YELLOW}Vídeos renderizados em: ./data/remotion/output/${NC}"
        echo
        print_warning "Certifique-se de que os registros DNS estão configurados:"
        echo -e "  ${YELLOW}$SUBDOMAIN_TRAEFIK.$DOMAIN${NC} → IP do servidor"
        echo -e "  ${YELLOW}$SUBDOMAIN_PORTAINER.$DOMAIN${NC} → IP do servidor"
        echo -e "  ${YELLOW}$SUBDOMAIN_N8N.$DOMAIN${NC} → IP do servidor"
        echo -e "  ${YELLOW}$SUBDOMAIN_REMOTION.$DOMAIN${NC} → IP do servidor"
    fi

    echo
    echo -e "${BLUE}Comandos Úteis:${NC}"
    echo -e "  Ver logs: ${YELLOW}docker-compose logs -f${NC}"
    echo -e "  Parar: ${YELLOW}docker-compose down${NC}"
    echo -e "  Reiniciar: ${YELLOW}docker-compose restart${NC}"
    echo -e "  Status: ${YELLOW}docker-compose ps${NC}"
    echo
}

# Função principal
main() {
    clear

    echo -e "${BLUE}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   Docker Stack - Traefik 2.11.3 + Portainer              ║
║   Script de Instalação Automática                        ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    check_root
    check_prerequisites
    cleanup_existing
    collect_information
    create_env_file
    prepare_directories
    update_traefik_config
    update_docker_compose
    start_services

    if check_services; then
        show_access_info

        echo
        print_success "Instalação concluída com sucesso!"
        echo
        print_info "Para mais informações, consulte o README.md"
    else
        echo
        print_error "Instalação concluída com avisos"
        print_info "Verifique os logs: docker-compose logs -f"
    fi
}

# Executar
main
