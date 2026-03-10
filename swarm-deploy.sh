#!/bin/bash

# Script de Deploy da Stack no Docker Swarm
# Traefik + Portainer

set -e

# Executar sempre no diretório onde está o script (para .env e stacks)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

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

# Carregar variáveis do .env
print_info "Carregando variáveis de ambiente do .env..."
# Usar export com xargs para evitar expansão de variáveis pelo bash
export $(grep -v '^#' .env | grep -v '^$' | xargs)
print_success "Variáveis de ambiente carregadas"

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

# Escolher a stack
print_header "Escolha a Stack"

echo -e "${YELLOW}Qual stack deseja gerenciar?${NC}"
echo "1) Traefik + Portainer (Infraestrutura)"
echo "2) WordPress"
echo "3) n8n (Automação de Workflows)"
echo
read -p "Stack [1]: " STACK_CHOICE
STACK_CHOICE=${STACK_CHOICE:-1}

case $STACK_CHOICE in
    1)
        STACK_NAME="traefik"
        STACK_FILE="docker-stack.yml"
        STACK_DESCRIPTION="Traefik + Portainer"
        ;;
    2)
        STACK_NAME="wordpress"
        STACK_FILE="docker-stack-wordpress.yml"
        STACK_DESCRIPTION="WordPress"

        # Verificar se a stack traefik está rodando
        if ! docker stack ls | grep -q "traefik"; then
            print_error "A stack Traefik precisa estar rodando antes do WordPress"
            print_info "Execute primeiro o deploy do Traefik (opção 1)"
            exit 1
        fi

        # Verificar variáveis WordPress
        WORDPRESS_VARS=("WORDPRESS_DB_NAME" "WORDPRESS_DB_USER" "WORDPRESS_DB_PASSWORD" "WORDPRESS_DB_ROOT_PASSWORD")
        for var in "${WORDPRESS_VARS[@]}"; do
            if [ -z "${!var}" ]; then
                print_error "Variável $var não definida no .env"
                print_info "Configure as variáveis do WordPress no arquivo .env"
                exit 1
            fi
        done

        # Criar diretórios WordPress
        print_info "Criando diretórios do WordPress..."
        mkdir -p data/wordpress/wp-content
        mkdir -p data/wordpress/uploads
        mkdir -p data/wordpress/mysql
        mkdir -p backups/wordpress/mysql
        mkdir -p backups/wordpress/files
        print_success "Diretórios criados"
        ;;
    3)
        STACK_NAME="n8n"
        STACK_FILE="docker-stack-n8n.yml"
        STACK_DESCRIPTION="n8n"

        # Verificar se a stack traefik está rodando
        if ! docker stack ls | grep -q "traefik"; then
            print_error "A stack Traefik precisa estar rodando antes do n8n"
            print_info "Execute primeiro o deploy do Traefik (opção 1)"
            exit 1
        fi

        # Verificar/gerar variáveis n8n
        if [ -z "$SUBDOMAIN_N8N" ]; then
            echo -e "${YELLOW}Exemplos: n8n, automacao, workflows${NC}"
            read -p "Subdomínio do n8n [n8n]: " SUBDOMAIN_N8N
            SUBDOMAIN_N8N=${SUBDOMAIN_N8N:-n8n}
            echo "SUBDOMAIN_N8N=$SUBDOMAIN_N8N" >> .env
            export SUBDOMAIN_N8N
            print_success "SUBDOMAIN_N8N definido como '$SUBDOMAIN_N8N'"
        fi

        if [ -z "$N8N_ENCRYPTION_KEY" ]; then
            if [ -f data/n8n/config ]; then
                print_error "Dados do n8n já existem (data/n8n/config), mas N8N_ENCRYPTION_KEY não está definida."
                print_info "Restaure N8N_ENCRYPTION_KEY no .env a partir de um backup, ou remova data/n8n para começar do zero (perda de workflows/credenciais)."
                print_info "Veja TROUBLESHOOTING.md: 'n8n: Mismatching encryption keys'"
                exit 1
            fi
            print_info "Gerando N8N_ENCRYPTION_KEY automaticamente..."
            N8N_ENCRYPTION_KEY=$(openssl rand -hex 32 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 64)
            echo "N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY" >> .env
            export N8N_ENCRYPTION_KEY
            print_success "N8N_ENCRYPTION_KEY gerada e salva no .env"
            print_warning "Faça backup do N8N_ENCRYPTION_KEY e não a altere após o primeiro deploy."
        else
            print_success "N8N_ENCRYPTION_KEY já configurada"
        fi

        # Criar diretório n8n com permissões corretas (n8n roda como uid 1000)
        print_info "Criando diretório de dados do n8n..."
        mkdir -p data/n8n
        chown -R 1000:1000 data/n8n
        print_success "Diretório criado com permissões corretas (uid 1000)"
        ;;
    *)
        print_error "Opção inválida"
        exit 1
        ;;
esac

# Opções de deploy
print_header "Opções de Deploy - ${STACK_DESCRIPTION}"

echo -e "${YELLOW}O que deseja fazer?${NC}"
echo "1) Deploy/Atualizar stack"
echo "2) Remover stack"
echo "3) Ver status da stack"
echo "4) Ver logs"
echo "5) Limpeza completa (stack + volumes + rede)"
echo
read -p "Opção [1]: " DEPLOY_OPTION
DEPLOY_OPTION=${DEPLOY_OPTION:-1}

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

        # Validar variáveis críticas antes do deploy
        if [ -z "$DOMAIN" ]; then
            print_error "Variável DOMAIN está vazia! Verifique o arquivo .env"
            exit 1
        fi
        if [ "$STACK_NAME" = "n8n" ]; then
            if [ -z "$SUBDOMAIN_N8N" ] || [ -z "$N8N_ENCRYPTION_KEY" ]; then
                print_error "Variáveis SUBDOMAIN_N8N ou N8N_ENCRYPTION_KEY estão vazias!"
                print_info "Execute o script novamente para configurá-las"
                exit 1
            fi
            print_info "Deploy com: SUBDOMAIN_N8N=$SUBDOMAIN_N8N | DOMAIN=$DOMAIN"
        fi

        # Deploy da stack
        print_info "Fazendo deploy da stack '$STACK_NAME'..."
        if [ "$STACK_NAME" = "n8n" ]; then
            print_info "Resolvendo variáveis do compose com .env..."
            if ! docker compose -f "$STACK_FILE" --env-file .env config > /tmp/n8n-stack-resolved.yml 2>/tmp/n8n-compose-config.err; then
                print_error "Falha ao resolver o compose do n8n. Verifique o .env e o arquivo $STACK_FILE."
                print_info "Saída do docker compose config:"
                [ -s /tmp/n8n-compose-config.err ] && cat /tmp/n8n-compose-config.err
                exit 1
            fi
            docker stack deploy -c /tmp/n8n-stack-resolved.yml --with-registry-auth "$STACK_NAME"
        else
            docker stack deploy -c "$STACK_FILE" --with-registry-auth "$STACK_NAME"
        fi

        print_success "Stack deployed!"

        # Aguardar serviços
        print_header "Aguardando Serviços"

        print_info "Aguardando serviços iniciarem (30s)..."
        sleep 30

        # Mostrar status
        echo
        docker stack services "$STACK_NAME"
        echo

        # Para n8n, verificar se o serviço subiu
        if [ "$STACK_NAME" = "n8n" ]; then
            REPLICAS=$(docker service ls -f name=n8n_n8n --format "{{.Replicas}}" 2>/dev/null | head -1)
            if [ "$REPLICAS" != "1/1" ]; then
                print_warning "O serviço n8n_n8n não está com 1/1 réplicas em execução (atual: ${REPLICAS:-?})."
                print_info "Para diagnosticar, execute:"
                echo -e "  ${YELLOW}docker service ps n8n_n8n --no-trunc${NC}"
                echo -e "  ${YELLOW}docker service logs n8n_n8n --tail 50${NC}"
                echo
            fi
        fi

        # Informações de acesso
        print_header "Informações de Acesso"

        echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║           SERVIÇOS DISPONÍVEIS                         ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
        echo

        if [ "$STACK_NAME" = "traefik" ]; then
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
        elif [ "$STACK_NAME" = "n8n" ]; then
            echo -e "${BLUE}n8n (Automação de Workflows):${NC}"
            echo -e "  URL: ${YELLOW}https://${SUBDOMAIN_N8N}.${DOMAIN}${NC}"
            echo -e "  ${YELLOW}Configure o usuário admin no primeiro acesso${NC}"
            echo
            print_warning "Certifique-se de que o DNS está configurado:"
            echo -e "  ${YELLOW}${SUBDOMAIN_N8N}.${DOMAIN}${NC} → IP do servidor"
        elif [ "$STACK_NAME" = "wordpress" ]; then
            echo -e "${BLUE}WordPress:${NC}"
            echo -e "  URL: ${YELLOW}https://${DOMAIN}${NC}"
            echo -e "  ${YELLOW}Configure o site no primeiro acesso${NC}"
            echo
            echo -e "${BLUE}Database:${NC}"
            echo -e "  Host: ${YELLOW}mysql${NC}"
            echo -e "  Database: ${YELLOW}${WORDPRESS_DB_NAME}${NC}"
            echo -e "  User: ${YELLOW}${WORDPRESS_DB_USER}${NC}"
            echo
            echo -e "${BLUE}Redis Cache:${NC}"
            echo -e "  Host: ${YELLOW}redis${NC}"
            echo -e "  Port: ${YELLOW}6379${NC}"
            echo
            print_warning "Certifique-se de que o DNS está configurado:"
            echo -e "  ${YELLOW}${DOMAIN}${NC} → IP do servidor"
            echo
            print_info "Para executar backup manualmente:"
            echo -e "  ${YELLOW}docker exec \$(docker ps -q -f name=wordpress_backup) /backup.sh${NC}"
        fi
        echo
        ;;

    2)
        # Remover stack
        print_header "Removendo Stack"

        if ! docker stack ls | grep -q "$STACK_NAME"; then
            print_error "Stack '$STACK_NAME' não encontrada"
            print_info "Faça o deploy primeiro: execute este script, escolha a stack e depois a opção 1 (Deploy/Atualizar)."
            exit 1
        fi

        read -p "Tem certeza que deseja remover a stack '$STACK_NAME'? [s/N]: " CONFIRM
        if [[ "$CONFIRM" =~ ^[Ss]$ ]]; then
            print_info "Removendo stack..."
            docker stack rm "$STACK_NAME"
            print_success "Stack removida!"

            print_info "Aguardando limpeza dos containers..."
            sleep 10

            # Limpar variáveis n8n do .env para forçar nova configuração no próximo deploy
            if [ "$STACK_NAME" = "n8n" ]; then
                sed -i '/^SUBDOMAIN_N8N=/d' .env
                sed -i '/^N8N_ENCRYPTION_KEY=/d' .env
                print_info "Variáveis SUBDOMAIN_N8N e N8N_ENCRYPTION_KEY removidas do .env"
                print_info "No próximo deploy do n8n, você será solicitado a configurá-las novamente"
            fi
        else
            print_info "Operação cancelada"
        fi
        ;;

    3)
        # Status
        print_header "Status da Stack"

        if ! docker stack ls | grep -q "$STACK_NAME"; then
            print_error "Stack '$STACK_NAME' não encontrada"
            print_info "Faça o deploy primeiro: execute este script, escolha a stack e depois a opção 1 (Deploy/Atualizar)."
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
            print_info "Faça o deploy primeiro: execute este script, escolha a stack e depois a opção 1 (Deploy/Atualizar)."
            exit 1
        fi

        if [ "$STACK_NAME" = "traefik" ]; then
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
        elif [ "$STACK_NAME" = "n8n" ]; then
            SERVICE="n8n"
        elif [ "$STACK_NAME" = "wordpress" ]; then
            echo -e "${YELLOW}Escolha o serviço:${NC}"
            echo "1) WordPress"
            echo "2) Nginx"
            echo "3) MySQL"
            echo "4) Redis"
            echo "5) Backup"
            echo
            read -p "Opção [1]: " SERVICE_OPTION
            SERVICE_OPTION=${SERVICE_OPTION:-1}

            case $SERVICE_OPTION in
                1) SERVICE="wordpress" ;;
                2) SERVICE="nginx" ;;
                3) SERVICE="mysql" ;;
                4) SERVICE="redis" ;;
                5) SERVICE="backup" ;;
                *) SERVICE="wordpress" ;;
            esac
        fi

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
        if [ "$STACK_NAME" = "traefik" ]; then
            echo "  - Remover a rede 'proxy'"
        fi
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

            if [ "$STACK_NAME" = "traefik" ]; then
                # Nota: Agora usamos bind mounts (./data), mas removemos volumes antigos caso existam
                docker volume rm traefik_traefik-certificates 2>/dev/null || true
                docker volume rm traefik_traefik-data 2>/dev/null || true
                docker volume rm traefik_portainer-data 2>/dev/null || true
                docker volume rm traefik-certificates 2>/dev/null || true
                docker volume rm traefik-data 2>/dev/null || true
                docker volume rm portainer-data 2>/dev/null || true
            elif [ "$STACK_NAME" = "n8n" ]; then
                docker volume rm n8n_n8n-data 2>/dev/null || true
            elif [ "$STACK_NAME" = "wordpress" ]; then
                docker volume rm wordpress_wordpress-data 2>/dev/null || true
                docker volume rm wordpress_mysql-data 2>/dev/null || true
                docker volume rm wordpress_redis-data 2>/dev/null || true
            fi

            print_success "Volumes antigos limpos (se existiam)"

            # Remover dados locais
            if [ "$STACK_NAME" = "traefik" ]; then
                print_warning "Remover dados locais em ./data/traefik e ./data/portainer?"
                read -p "Digite 'SIM' para confirmar: " CONFIRM_DATA
                if [ "$CONFIRM_DATA" = "SIM" ]; then
                    rm -rf data/traefik/* data/portainer/*
                    print_success "Dados locais removidos"
                fi
            elif [ "$STACK_NAME" = "n8n" ]; then
                print_warning "Remover dados locais em ./data/n8n?"
                read -p "Digite 'SIM' para confirmar: " CONFIRM_DATA
                if [ "$CONFIRM_DATA" = "SIM" ]; then
                    rm -rf data/n8n/*
                    print_success "Dados locais removidos"
                fi
                # Limpar variáveis n8n do .env para forçar nova configuração no próximo deploy
                sed -i '/^SUBDOMAIN_N8N=/d' .env
                sed -i '/^N8N_ENCRYPTION_KEY=/d' .env
                print_info "Variáveis SUBDOMAIN_N8N e N8N_ENCRYPTION_KEY removidas do .env"
                print_info "No próximo deploy do n8n, você será solicitado a configurá-las novamente"
            elif [ "$STACK_NAME" = "wordpress" ]; then
                print_warning "Remover dados locais em ./data/wordpress e ./backups/wordpress?"
                read -p "Digite 'SIM' para confirmar: " CONFIRM_DATA
                if [ "$CONFIRM_DATA" = "SIM" ]; then
                    rm -rf data/wordpress/* backups/wordpress/*
                    print_success "Dados locais removidos"
                fi
            fi

            # Remover rede (apenas para traefik)
            if [ "$STACK_NAME" = "traefik" ]; then
                print_info "Removendo rede 'proxy'..."
                docker network rm proxy 2>/dev/null && print_success "Rede 'proxy' removida" || print_warning "Rede 'proxy' não encontrada"
            fi

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
