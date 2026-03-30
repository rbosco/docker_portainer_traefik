#!/bin/bash

# Script de inicialização do Docker Swarm
# Para stack Traefik + Portainer

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

# Overlay Swarm com nome exato "proxy" (docker-stack.yml). Evita falso positivo de "grep proxy".
ensure_swarm_proxy_network() {
    if ! docker network inspect proxy &>/dev/null; then
        docker network create --driver overlay --attachable proxy
        print_success "Rede overlay 'proxy' criada"
        return 0
    fi
    local driver scope
    driver=$(docker network inspect -f '{{.Driver}}' proxy 2>/dev/null)
    scope=$(docker network inspect -f '{{.Scope}}' proxy 2>/dev/null)
    if [ "$driver" = "overlay" ] && [ "$scope" = "swarm" ]; then
        print_success "Rede overlay Swarm 'proxy' já existe"
        return 0
    fi
    print_error "Rede 'proxy' existe mas não é overlay Swarm (driver=$driver, scope=$scope)."
    print_info "Após docker compose, 'proxy' costuma ser bridge. Remova e crie a overlay:"
    print_info "  docker compose down && docker network rm proxy"
    print_info "  docker network create --driver overlay --attachable proxy"
    exit 1
}

# Banner
clear
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   Docker Swarm - Traefik 2.10.7 + Portainer              ║
║   Script de Inicialização                                ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificar se já está em modo Swarm
print_header "Verificando Status do Swarm"

if docker info 2>/dev/null | grep -q "Swarm: active"; then
    print_warning "Docker Swarm já está ativo neste node"

    # Mostrar informações do Swarm
    echo
    docker node ls 2>/dev/null || print_info "Este node não é um manager"
    echo

    read -p "Deseja reinicializar o Swarm? [s/N]: " REINIT
    if [[ "$REINIT" =~ ^[Ss]$ ]]; then
        print_info "Deixando o Swarm..."
        docker swarm leave --force
        print_success "Swarm desativado"
    else
        print_info "Mantendo configuração atual do Swarm"
        exit 0
    fi
fi

# Escolher modo de inicialização
print_header "Configuração do Cluster"

echo -e "${YELLOW}Escolha o tipo de node:${NC}"
echo "1) Manager (Primeiro node do cluster ou único)"
echo "2) Worker (Adicionar a um cluster existente)"
echo "3) Manager adicional (Adicionar manager a cluster existente)"
echo
read -p "Opção [1]: " NODE_TYPE
NODE_TYPE=${NODE_TYPE:-1}

if [ "$NODE_TYPE" = "1" ]; then
    # Inicializar como primeiro manager
    print_header "Inicializando Swarm como Manager"

    # Detectar IP principal
    DEFAULT_IP=$(hostname -I | awk '{print $1}')

    echo -e "${YELLOW}Endereço IP deste servidor:${NC}"
    read -p "IP para anunciar [$DEFAULT_IP]: " ADVERTISE_ADDR
    ADVERTISE_ADDR=${ADVERTISE_ADDR:-$DEFAULT_IP}

    print_info "Inicializando Swarm..."
    docker swarm init --advertise-addr "$ADVERTISE_ADDR"

    print_success "Swarm inicializado com sucesso!"

    # Mostrar tokens
    echo
    print_header "Tokens de Acesso"

    echo -e "${YELLOW}Token para adicionar WORKERS:${NC}"
    WORKER_TOKEN=$(docker swarm join-token worker -q)
    echo -e "${GREEN}docker swarm join --token $WORKER_TOKEN $ADVERTISE_ADDR:2377${NC}"

    echo
    echo -e "${YELLOW}Token para adicionar MANAGERS:${NC}"
    MANAGER_TOKEN=$(docker swarm join-token manager -q)
    echo -e "${GREEN}docker swarm join --token $MANAGER_TOKEN $ADVERTISE_ADDR:2377${NC}"

    # Salvar tokens em arquivo
    cat > swarm-tokens.txt << EOL
# Docker Swarm Tokens
# Gerado em: $(date)

# Adicionar Worker:
docker swarm join --token $WORKER_TOKEN $ADVERTISE_ADDR:2377

# Adicionar Manager:
docker swarm join --token $MANAGER_TOKEN $ADVERTISE_ADDR:2377
EOL

    print_success "Tokens salvos em: swarm-tokens.txt"

    # Criar rede overlay Swarm (nome exato: proxy)
    print_header "Criando Rede Overlay"

    ensure_swarm_proxy_network

    # Preparar estrutura de arquivos e diretórios
    print_header "Preparando Estrutura de Dados"

    # Copiar .env.example se .env não existir
    if [ ! -f .env ]; then
        if [ -f .env.example ]; then
            print_info "Criando arquivo .env a partir de .env.example..."
            cp .env.example .env
            print_success "Arquivo .env criado"
            print_warning "IMPORTANTE: Edite o arquivo .env e configure suas variáveis!"
            echo
        else
            print_warning "Arquivo .env.example não encontrado"
            print_info "Você precisará criar o arquivo .env manualmente"
        fi
    else
        print_success "Arquivo .env já existe"
    fi

    # Criar estrutura de diretórios
    print_info "Criando diretórios de dados..."
    mkdir -p data/traefik data/portainer
    print_success "Diretórios criados: data/traefik, data/portainer"

    # Criar acme.json com permissões corretas (JSON vazio; Traefik espera ficheiro JSON válido)
    if [ ! -f data/traefik/acme.json ]; then
        print_info "Criando arquivo acme.json..."
        echo '{}' > data/traefik/acme.json
        chmod 600 data/traefik/acme.json
        print_success "Arquivo acme.json criado com permissões 600"
    else
        print_info "Arquivo acme.json já existe"
        # Garantir permissões corretas
        chmod 600 data/traefik/acme.json
        print_success "Permissões do acme.json verificadas (600)"
    fi

    # Labels no node
    print_header "Configurando Labels do Node"

    NODE_ID=$(docker node ls -q)
    docker node update --label-add type=manager "$NODE_ID"
    print_success "Label 'type=manager' adicionada"

elif [ "$NODE_TYPE" = "2" ] || [ "$NODE_TYPE" = "3" ]; then
    # Juntar-se a um cluster existente
    print_header "Juntando-se ao Cluster Swarm"

    echo -e "${YELLOW}Informações do Manager:${NC}"
    read -p "IP do Manager: " MANAGER_IP

    if [ "$NODE_TYPE" = "2" ]; then
        read -p "Token de Worker: " TOKEN
        ROLE="worker"
    else
        read -p "Token de Manager: " TOKEN
        ROLE="manager"
    fi

    print_info "Juntando-se ao cluster como $ROLE..."
    docker swarm join --token "$TOKEN" "$MANAGER_IP:2377"

    print_success "Node adicionado ao cluster com sucesso!"
fi

# Status final
print_header "Status do Cluster"

docker node ls 2>/dev/null || docker info | grep -A5 "Swarm:"

echo
print_success "Inicialização do Swarm concluída!"
echo
print_info "Próximos passos:"
echo "  1. ${YELLOW}Edite o arquivo .env${NC} e configure:"
echo "     - DOMAIN (seu domínio)"
echo "     - SUBDOMAIN_TRAEFIK e SUBDOMAIN_PORTAINER (subdomínios)"
echo "     - ACME_EMAIL (email para Let's Encrypt)"
echo "     - TRAEFIK_USER (senha do dashboard)"
echo
echo "  2. Execute: ${GREEN}./swarm-deploy.sh${NC}"
echo
