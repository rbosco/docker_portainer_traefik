#!/bin/bash

# Script de Deploy da Stack no Docker Swarm
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
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   Docker Swarm Stack Deploy                              ║
║   Traefik 2.11.3 + Portainer                             ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# Verificar se está em modo Swarm
print_header "Verificando Pré-requisitos"

if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
    print_error "Docker Swarm não está ativo"
    print_info "Execute primeiro: ./swarm-init.sh"
    exit 1
fi

print_success "Docker Swarm ativo"

# Verificar se é manager
if ! docker node ls &>/dev/null; then
    print_error "Este node não é um manager"
    print_info "Execute o deploy a partir de um node manager"
    exit 1
fi

print_success "Node é manager"

# Verificar arquivo .env
if [ ! -f .env ]; then
    print_error "Arquivo .env não encontrado"
    print_info "Execute: cp .env.example .env"
    print_info "E configure as variáveis necessárias"
    exit 1
fi

print_success "Arquivo .env encontrado"

# Carregar variáveis
source .env

# Verificar variáveis obrigatórias
REQUIRED_VARS=("DOMAIN" "TRAEFIK_USER")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        print_error "Variável $var não definida no .env"
        exit 1
    fi
done

print_success "Variáveis de ambiente configuradas"

# Verificar rede overlay
print_header "Verificando Rede Overlay"

if ! docker network ls | grep -q "proxy"; then
    print_info "Criando rede overlay 'proxy'..."
    docker network create --driver overlay --attachable proxy
    print_success "Rede 'proxy' criada"
else
    print_success "Rede 'proxy' já existe"
fi

# Opções de deploy
print_header "Opções de Deploy"

echo -e "${YELLOW}O que deseja fazer?${NC}"
echo "1) Deploy/Atualizar stack"
echo "2) Remover stack"
echo "3) Ver status da stack"
echo "4) Ver logs"
echo "5) Limpeza completa (stack + volumes + rede)"
echo
read -p "Opção [1]: " DEPLOY_OPTION
DEPLOY_OPTION=${DEPLOY_OPTION:-1}

STACK_NAME="traefik"

case $DEPLOY_OPTION in
    1)
        # Deploy
        print_header "Fazendo Deploy da Stack"

        # Verificar se stack já existe
        if docker stack ls | grep -q "$STACK_NAME"; then
            print_warning "Stack '$STACK_NAME' já existe"
            read -p "Deseja atualizar? [S/n]: " UPDATE
            UPDATE=${UPDATE:-S}
            if [[ ! "$UPDATE" =~ ^[Ss]$ ]]; then
                print_info "Deploy cancelado"
                exit 0
            fi
        fi

        # Deploy da stack
        print_info "Fazendo deploy da stack '$STACK_NAME'..."
        docker stack deploy -c docker-stack.yml --with-registry-auth "$STACK_NAME"

        print_success "Stack deployed!"

        # Aguardar serviços
        print_header "Aguardando Serviços"

        print_info "Aguardando serviços iniciarem (30s)..."
        sleep 30

        # Mostrar status
        echo
        docker stack services "$STACK_NAME"
        echo

        # Informações de acesso
        print_header "Informações de Acesso"

        echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║           SERVIÇOS DISPONÍVEIS                         ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
        echo
        echo -e "${BLUE}Traefik Dashboard:${NC}"
        echo -e "  URL: ${YELLOW}https://pr.${DOMAIN}${NC}"
        echo -e "  ${YELLOW}(Autenticação configurada via TRAEFIK_USER)${NC}"
        echo
        echo -e "${BLUE}Portainer:${NC}"
        echo -e "  URL: ${YELLOW}https://painel.${DOMAIN}${NC}"
        echo -e "  ${YELLOW}Configure o usuário admin no primeiro acesso${NC}"
        echo
        print_warning "Certifique-se de que os DNS estão configurados:"
        echo -e "  ${YELLOW}pr.${DOMAIN}${NC} → IP do servidor"
        echo -e "  ${YELLOW}painel.${DOMAIN}${NC} → IP do servidor"
        echo
        ;;

    2)
        # Remover stack
        print_header "Removendo Stack"

        if ! docker stack ls | grep -q "$STACK_NAME"; then
            print_error "Stack '$STACK_NAME' não encontrada"
            exit 1
        fi

        read -p "Tem certeza que deseja remover a stack '$STACK_NAME'? [s/N]: " CONFIRM
        if [[ "$CONFIRM" =~ ^[Ss]$ ]]; then
            print_info "Removendo stack..."
            docker stack rm "$STACK_NAME"
            print_success "Stack removida!"

            print_info "Aguardando limpeza dos containers..."
            sleep 10
        else
            print_info "Operação cancelada"
        fi
        ;;

    3)
        # Status
        print_header "Status da Stack"

        if ! docker stack ls | grep -q "$STACK_NAME"; then
            print_error "Stack '$STACK_NAME' não encontrada"
            exit 1
        fi

        echo -e "${YELLOW}Serviços:${NC}"
        docker stack services "$STACK_NAME"

        echo
        echo -e "${YELLOW}Tasks (containers):${NC}"
        docker stack ps "$STACK_NAME" --no-trunc

        echo
        echo -e "${YELLOW}Redes:${NC}"
        docker network ls | grep -E "NETWORK|proxy|${STACK_NAME}"
        ;;

    4)
        # Logs
        print_header "Logs da Stack"

        if ! docker stack ls | grep -q "$STACK_NAME"; then
            print_error "Stack '$STACK_NAME' não encontrada"
            exit 1
        fi

        echo -e "${YELLOW}Escolha o serviço:${NC}"
        echo "1) Traefik"
        echo "2) Portainer"
        echo "3) Agent"
        echo
        read -p "Opção [1]: " SERVICE_OPTION
        SERVICE_OPTION=${SERVICE_OPTION:-1}

        case $SERVICE_OPTION in
            1) SERVICE="traefik" ;;
            2) SERVICE="portainer" ;;
            3) SERVICE="agent" ;;
            *) SERVICE="traefik" ;;
        esac

        print_info "Exibindo logs do serviço: ${STACK_NAME}_${SERVICE}"
        echo
        docker service logs -f "${STACK_NAME}_${SERVICE}"
        ;;

    5)
        # Limpeza completa
        print_header "Limpeza Completa"

        echo -e "${RED}ATENÇÃO: Esta opção irá:${NC}"
        echo "  - Remover a stack '$STACK_NAME'"
        echo "  - Remover todos os volumes (dados persistentes)"
        echo "  - Remover a rede 'proxy'"
        echo "  ${RED}TODOS OS DADOS SERÃO PERDIDOS!${NC}"
        echo

        read -p "Tem ABSOLUTA CERTEZA que deseja continuar? Digite 'LIMPAR' para confirmar: " CONFIRM

        if [ "$CONFIRM" = "LIMPAR" ]; then
            # Remover stack
            if docker stack ls | grep -q "$STACK_NAME"; then
                print_info "Removendo stack '$STACK_NAME'..."
                docker stack rm "$STACK_NAME"
                print_success "Stack removida"

                print_info "Aguardando limpeza dos containers..."
                sleep 15
            else
                print_warning "Stack '$STACK_NAME' não encontrada"
            fi

            # Remover volumes antigos (se existirem)
            print_info "Removendo volumes antigos (se existirem)..."
            # Nota: Agora usamos bind mounts (./data), mas removemos volumes antigos caso existam
            docker volume rm traefik_traefik-certificates 2>/dev/null || true
            docker volume rm traefik_traefik-data 2>/dev/null || true
            docker volume rm traefik_portainer-data 2>/dev/null || true
            docker volume rm traefik-certificates 2>/dev/null || true
            docker volume rm traefik-data 2>/dev/null || true
            docker volume rm portainer-data 2>/dev/null || true
            print_success "Volumes antigos limpos (se existiam)"

            # Remover rede
            print_info "Removendo rede 'proxy'..."
            docker network rm proxy 2>/dev/null && print_success "Rede 'proxy' removida" || print_warning "Rede 'proxy' não encontrada"

            echo
            print_success "Limpeza completa finalizada!"
            echo
            print_info "Para reinstalar, execute novamente este script com a opção 1"
        else
            print_info "Limpeza cancelada"
        fi
        ;;

    *)
        print_error "Opção inválida"
        exit 1
        ;;
esac

echo
print_info "Comandos úteis:"
echo "  Ver serviços: ${YELLOW}docker stack services $STACK_NAME${NC}"
echo "  Ver logs: ${YELLOW}docker service logs -f ${STACK_NAME}_traefik${NC}"
echo "  Escalar serviço: ${YELLOW}docker service scale ${STACK_NAME}_portainer=2${NC}"
echo "  Atualizar serviço: ${YELLOW}docker service update ${STACK_NAME}_traefik${NC}"
echo
