#!/bin/bash

# Script de Limpeza Completa
# Remove todos os containers, volumes e redes do projeto
# Traefik + Portainer

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Banner
clear
echo -e "${RED}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   Script de Limpeza Completa                             ║
║   Docker + Traefik + Portainer                           ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

print_header "⚠️  ATENÇÃO - OPERAÇÃO DESTRUTIVA"

echo -e "${RED}Este script irá remover COMPLETAMENTE:${NC}"
echo
echo "  ${YELLOW}Docker Compose:${NC}"
echo "    - Todos os containers (traefik, portainer)"
echo "    - Volumes de dados persistentes"
echo "    - Rede proxy"
echo
echo "  ${YELLOW}Docker Swarm:${NC}"
echo "    - Stack 'traefik' completa"
echo "    - Volumes Swarm (traefik-certificates, traefik-data, portainer-data)"
echo "    - Rede overlay 'proxy'"
echo
echo "  ${YELLOW}Dados Locais:${NC}"
echo "    - Diretório data/traefik"
echo "    - Diretório data/portainer"
echo
echo -e "${RED}═══════════════════════════════════════════════════${NC}"
echo -e "${RED}  TODOS OS DADOS SERÃO PERMANENTEMENTE PERDIDOS!  ${NC}"
echo -e "${RED}═══════════════════════════════════════════════════${NC}"
echo

# Confirmação de segurança
read -p "Deseja realmente continuar? Digite 'SIM' em maiúsculas para confirmar: " CONFIRM

if [ "$CONFIRM" != "SIM" ]; then
    print_info "Operação cancelada"
    echo
    print_info "Nenhuma alteração foi feita"
    exit 0
fi

echo
print_warning "Última chance! Esta operação é IRREVERSÍVEL!"
read -p "Digite 'LIMPAR TUDO' para confirmar: " FINAL_CONFIRM

if [ "$FINAL_CONFIRM" != "LIMPAR TUDO" ]; then
    print_info "Operação cancelada"
    echo
    print_info "Nenhuma alteração foi feita"
    exit 0
fi

# Iniciar limpeza
print_header "Iniciando Limpeza Completa"

# 1. Detectar modo
IS_SWARM=false
if docker info 2>/dev/null | grep -q "Swarm: active"; then
    IS_SWARM=true
    print_info "Docker Swarm detectado - limpando modo Swarm"
else
    print_info "Docker Swarm não ativo - limpando modo Compose"
fi

# 2. Limpar Docker Swarm (se ativo)
if [ "$IS_SWARM" = true ]; then
    print_header "Limpando Docker Swarm"

    # Remover stack
    if docker stack ls 2>/dev/null | grep -q "traefik"; then
        print_info "Removendo stack 'traefik'..."
        docker stack rm traefik
        print_success "Stack removida"

        print_info "Aguardando limpeza dos containers..."
        sleep 15
    else
        print_warning "Stack 'traefik' não encontrada"
    fi

    # Remover volumes Swarm
    print_info "Removendo volumes do Swarm..."
    docker volume rm traefik_traefik-certificates 2>/dev/null && print_success "Volume traefik_traefik-certificates removido" || true
    docker volume rm traefik_traefik-data 2>/dev/null && print_success "Volume traefik_traefik-data removido" || true
    docker volume rm traefik_portainer-data 2>/dev/null && print_success "Volume traefik_portainer-data removido" || true

    # Remover rede overlay
    print_info "Removendo rede overlay 'proxy'..."
    docker network rm proxy 2>/dev/null && print_success "Rede 'proxy' removida" || print_warning "Rede 'proxy' não encontrada"
fi

# 3. Limpar Docker Compose
print_header "Limpando Docker Compose"

# Parar e remover containers
if [ -f docker-compose.yml ]; then
    print_info "Parando e removendo containers do Compose..."
    docker-compose down -v 2>/dev/null && print_success "Containers do Compose removidos" || print_warning "Nenhum container do Compose encontrado"
else
    print_warning "docker-compose.yml não encontrado"
fi

# Remover volumes locais
print_info "Removendo volumes do Compose..."
docker volume rm docker_portainer_traefik_proxy 2>/dev/null || true

# Remover rede bridge
print_info "Removendo rede bridge 'proxy'..."
docker network rm proxy 2>/dev/null || print_warning "Rede 'proxy' não encontrada"

# 4. Limpar diretórios de dados locais
print_header "Limpando Dados Locais"

if [ -d "data/traefik" ]; then
    print_info "Removendo data/traefik..."
    rm -rf data/traefik
    print_success "Diretório data/traefik removido"
fi

if [ -d "data/portainer" ]; then
    print_info "Removendo data/portainer..."
    rm -rf data/portainer
    print_success "Diretório data/portainer removido"
fi

# Recriar estrutura vazia
print_info "Recriando estrutura de diretórios..."
mkdir -p data/traefik data/portainer
touch data/traefik/acme.json
chmod 600 data/traefik/acme.json
print_success "Estrutura de diretórios recriada"

# 5. Limpar arquivo .env (opcional)
print_header "Arquivo de Configuração"

if [ -f .env ]; then
    read -p "Deseja também remover o arquivo .env? [s/N]: " REMOVE_ENV
    if [[ "$REMOVE_ENV" =~ ^[Ss]$ ]]; then
        rm .env
        print_success "Arquivo .env removido"
        print_info "Use .env.example como referência para recriar"
    else
        print_info "Arquivo .env mantido"
    fi
fi

# 6. Resumo final
print_header "Limpeza Concluída!"

echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           LIMPEZA FINALIZADA COM SUCESSO               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════${NC}"
echo

print_success "Todos os containers foram removidos"
print_success "Todos os volumes foram removidos"
print_success "Todas as redes foram removidas"
print_success "Dados locais foram limpos"
echo

print_info "Para reinstalar o projeto:"
echo
echo -e "  ${YELLOW}Docker Compose:${NC}"
echo "    ./setup.sh"
echo
echo -e "  ${YELLOW}Docker Swarm:${NC}"
echo "    ./swarm-init.sh"
echo "    ./swarm-deploy.sh"
echo

print_warning "Não esqueça de configurar o arquivo .env antes de reinstalar!"
echo
