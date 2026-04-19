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

# Helper global: cria ou atualiza uma chave no .env e exporta no shell atual.
_upsert_env() {
    local k="$1" v="$2"
    export "${k}=${v}"
    if grep -q "^${k}=" .env 2>/dev/null; then
        sed -i.bak "s#^${k}=.*#${k}=${v}#" .env
    else
        echo "${k}=${v}" >> .env
    fi
}

# Se DOMAIN ja estiver configurado no .env (nao vazio e diferente de 'localhost'),
# usa o valor atual sem perguntar. Caso contrario, solicita ao usuario e grava no .env.
ensure_domain() {
    local current="${DOMAIN:-}"
    if [ -n "$current" ] && [ "$current" != "localhost" ]; then
        print_success "DOMAIN=${current} (usando valor do .env)"
        return 0
    fi
    print_warning "DOMAIN nao configurado no .env (vazio ou 'localhost')"
    read -p "Informe o dominio principal (ex.: exemplo.com): " NEW_DOMAIN
    if [ -z "$NEW_DOMAIN" ] || [ "$NEW_DOMAIN" = "localhost" ]; then
        print_error "DOMAIN invalido. Informe um dominio real."
        exit 1
    fi
    _upsert_env "DOMAIN" "$NEW_DOMAIN"
    print_success "DOMAIN=${NEW_DOMAIN} gravado no .env"
}

# docker-stack*.yml usa rede externa nome exato "proxy" (overlay Swarm).
# "docker network ls | grep proxy" dá falso positivo (ex.: docker_portainer_traefik_proxy).
ensure_swarm_proxy_network() {
    if ! docker network inspect proxy &>/dev/null; then
        print_info "Criando rede overlay Swarm 'proxy'..."
        docker network create --driver overlay --attachable proxy
        print_success "Rede 'proxy' criada"
        return 0
    fi
    local driver scope
    driver=$(docker network inspect -f '{{.Driver}}' proxy 2>/dev/null)
    scope=$(docker network inspect -f '{{.Scope}}' proxy 2>/dev/null)
    if [ "$driver" = "overlay" ] && [ "$scope" = "swarm" ]; then
        print_success "Rede overlay Swarm 'proxy' OK"
        return 0
    fi
    print_error "Existe uma rede 'proxy', mas não é overlay Swarm (driver=$driver, scope=$scope)."
    print_info "Comum após ./setup.sh ou docker compose: 'proxy' fica em bridge local."
    print_info "Pare o compose e remova a rede, depois volte a executar este script:"
    print_info "  docker compose down"
    print_info "  docker network rm proxy"
    print_info "Ou crie manualmente: docker network create --driver overlay --attachable proxy"
    exit 1
}

# Bind-mounts do docker-stack.yml (Traefik): ficheiro acme.json tem de existir no host antes do deploy Swarm.
ensure_traefik_stack_host_paths() {
    mkdir -p data/traefik data/portainer
    if [ ! -f data/traefik/acme.json ]; then
        print_info "Criando data/traefik/acme.json (necessário para o volume bind da stack Traefik)..."
        echo '{}' > data/traefik/acme.json
        print_success "acme.json criado"
    fi
    chmod 600 data/traefik/acme.json
    print_success "Caminhos locais Traefik/Portainer OK (data/traefik, data/portainer)"
}

# Remotion: clonar template oficial se ./remotion ainda nao existir.
# Fonte: https://github.com/remotion-dev/template-render-server
ensure_remotion_repo() {
    if [ -d remotion/.git ] || [ -f remotion/Dockerfile ]; then
        print_success "Projeto ./remotion ja existe (nao sera sobrescrito)"
        return 0
    fi
    print_warning "Pasta ./remotion nao encontrada."
    print_info "Fonte: https://github.com/remotion-dev/template-render-server (Express + Studio + Dockerfile)"
    read -p "Clonar o template oficial em ./remotion agora? [S/n]: " CLONE_CHOICE
    CLONE_CHOICE=${CLONE_CHOICE:-S}
    if [[ ! "$CLONE_CHOICE" =~ ^[Ss]$ ]]; then
        print_error "Projeto Remotion e necessario para buildar a imagem. Abortando."
        exit 1
    fi
    if ! command -v git >/dev/null 2>&1; then
        print_error "git nao encontrado no PATH. Instale git e tente novamente."
        exit 1
    fi
    git clone --depth 1 https://github.com/remotion-dev/template-render-server remotion
    print_success "Template clonado em ./remotion"
    print_info "Customize ./remotion/src/ com suas proprias compositions antes de produzir videos reais."
}

# Mostra contexto/endpoint Docker ativo para evitar deploy em daemon errado.
show_docker_endpoint() {
    local ctx host
    ctx=$(docker context show 2>/dev/null || echo default)
    host=$(docker context inspect "$ctx" --format '{{.Endpoints.docker.Host}}' 2>/dev/null)
    [ -n "$DOCKER_HOST" ] && host="$DOCKER_HOST (via DOCKER_HOST)"
    print_info "Docker context: ${ctx} | endpoint: ${host:-unix:///var/run/docker.sock}"
}

# Guard: se DOCKER_HOST ou DOCKER_CONTEXT nao forem default, oferece forcar socket local.
# Previne deploys "sumidos" em outro daemon (causa comum: SSH com DOCKER_CONTEXT herdado).
ensure_local_docker() {
    # Sessoes SSH com DOCKER_CONTEXT remoto herdado: forcar socket local sem prompt (CI / automacao)
    if [ "${SWARM_DEPLOY_FORCE_LOCAL:-}" = "1" ]; then
        unset DOCKER_HOST
        export DOCKER_CONTEXT=default
        print_info "SWARM_DEPLOY_FORCE_LOCAL=1: usando DOCKER_CONTEXT=default (socket local)."
        show_docker_endpoint
        if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
            print_error "Swarm nao esta ativo no socket local. Execute ./swarm-init.sh"
            exit 1
        fi
        return 0
    fi

    show_docker_endpoint
    local ctx="${DOCKER_CONTEXT:-$(docker context show 2>/dev/null || echo default)}"
    if [ -z "$DOCKER_HOST" ] && [ "$ctx" = "default" ]; then
        return 0
    fi
    print_warning "Docker CLI aponta para endpoint NAO-local."
    print_warning "'docker stack deploy' subira a stack NESSE endpoint, nao no host atual."
    echo
    echo "1) Continuar assim mesmo (deploy no endpoint remoto)"
    echo "2) Forcar socket local (unset DOCKER_HOST, DOCKER_CONTEXT=default) e revalidar"
    echo "3) Abortar"
    read -p "Opcao [2]: " CTX_CHOICE
    CTX_CHOICE=${CTX_CHOICE:-2}
    case $CTX_CHOICE in
        1) print_warning "Prosseguindo com endpoint remoto" ;;
        2)
            unset DOCKER_HOST
            export DOCKER_CONTEXT=default
            print_info "Reavaliando Swarm no socket local..."
            if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
                print_error "Swarm nao esta ativo no socket local. Execute ./swarm-init.sh"
                exit 1
            fi
            show_docker_endpoint
            print_success "Usando socket local (default)"
            ;;
        *) print_info "Abortado"; exit 0 ;;
    esac
}

# Alinha DOCKER_API_VERSION com a maior API suportada pelo daemon.
# Resolve o erro "client version X.Y is too new. Maximum supported API version is Z"
# quando o CLI eh mais novo que o dockerd da VPS.
ensure_docker_api_compat() {
    local server_api
    server_api=$(docker version --format '{{.Server.APIVersion}}' 2>/dev/null || true)
    if [ -z "$server_api" ]; then
        return 0
    fi
    if [ -n "$DOCKER_API_VERSION" ]; then
        print_info "DOCKER_API_VERSION ja definido: $DOCKER_API_VERSION (server: $server_api)"
        return 0
    fi
    export DOCKER_API_VERSION="$server_api"
    print_info "DOCKER_API_VERSION=$server_api (alinhado com o daemon)"
}

# Remotion: buildar imagem local a partir de ./remotion/Dockerfile.
ensure_remotion_image() {
    if [ ! -f remotion/Dockerfile ]; then
        print_error "remotion/Dockerfile nao encontrado (o template oficial ja traz um)."
        exit 1
    fi
    if docker image inspect remotion-local:latest >/dev/null 2>&1; then
        read -p "Imagem 'remotion-local:latest' ja existe. Rebuildar? [s/N]: " REBUILD
        REBUILD=${REBUILD:-N}
        if [[ ! "$REBUILD" =~ ^[Ss]$ ]]; then
            print_info "Usando imagem existente 'remotion-local:latest'"
            return 0
        fi
    fi
    print_info "Buildando 'remotion-local:latest' a partir de ./remotion (pode demorar 5-10 min na 1a vez)..."

    local build_log
    build_log=$(mktemp 2>/dev/null || echo "/tmp/remotion-build-$$.log")
    if docker build -t remotion-local:latest ./remotion 2>&1 | tee "$build_log"; then
        rm -f "$build_log"
        print_success "Imagem 'remotion-local:latest' construida"
        return 0
    fi

    # Fallback: CLI mais novo que daemon? Detectar e refazer com DOCKER_API_VERSION.
    if grep -q "client version .* is too new" "$build_log" 2>/dev/null; then
        print_warning "Docker CLI e mais novo que o daemon. Tentando alinhar DOCKER_API_VERSION..."
        ensure_docker_api_compat
        if [ -n "$DOCKER_API_VERSION" ]; then
            print_info "Re-tentando build com DOCKER_API_VERSION=$DOCKER_API_VERSION..."
            if docker build -t remotion-local:latest ./remotion; then
                rm -f "$build_log"
                print_success "Imagem 'remotion-local:latest' construida"
                print_warning "Recomendacao: atualize o Docker Engine (curl -fsSL https://get.docker.com | sh)"
                return 0
            fi
        fi
    fi

    rm -f "$build_log"
    print_error "Falha ao buildar 'remotion-local:latest'"
    print_info "Verifique: docker version  (compare Client vs Server)"
    print_info "Workaround: export DOCKER_API_VERSION=\$(docker version --format '{{.Server.APIVersion}}')"
    print_info "Fix definitivo: atualize o Docker Engine na VPS"
    exit 1
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

# Guard: confirmar que o CLI aponta para o daemon local (evita deploy em outro host)
ensure_local_docker

# Alinhar API version (resolve mismatch cliente novo x daemon antigo)
ensure_docker_api_compat

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

# Carregar variáveis do .env preservando caracteres especiais ($$, $, etc.)
print_info "Carregando variáveis de ambiente do .env..."
while IFS='=' read -r key value; do
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    # Converter $$ para $ (convenção Docker Compose no .env)
    value="${value//\$\$/\$}"
    export "$key"="$value"
done < .env
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

# Verificar / criar rede overlay Swarm (nome exato: proxy)
print_header "Verificando Rede Overlay Swarm"

ensure_swarm_proxy_network

# Escolher a stack
print_header "Escolha a Stack"

echo -e "${YELLOW}Qual stack deseja gerenciar?${NC}"
echo "1) Traefik + Portainer (Infraestrutura)"
echo "2) WordPress"
echo "3) n8n (Automação de Workflows)"
echo "4) Remotion + MinIO (Studio + Render + Storage S3)"
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

        # WordPress: defaults + passwords seguras se faltar (ver .env.example secção WordPress)
        _wp_upsert_env() { _upsert_env "$@"; }
        if [ -z "$WORDPRESS_DB_NAME" ]; then
            _wp_upsert_env "WORDPRESS_DB_NAME" "wordpress"
            print_info "WORDPRESS_DB_NAME definido (wordpress) e gravado no .env"
        fi
        if [ -z "$WORDPRESS_DB_USER" ]; then
            _wp_upsert_env "WORDPRESS_DB_USER" "wordpress"
            print_info "WORDPRESS_DB_USER definido (wordpress) e gravado no .env"
        fi
        if [ -z "$WORDPRESS_DB_PASSWORD" ] || [ "$WORDPRESS_DB_PASSWORD" = "change_this_secure_password" ]; then
            WORDPRESS_DB_PASSWORD=$(openssl rand -hex 24 2>/dev/null || head -c 24 /dev/urandom | xxd -p -c 256 2>/dev/null | head -c 48)
            _wp_upsert_env "WORDPRESS_DB_PASSWORD" "$WORDPRESS_DB_PASSWORD"
            print_info "WORDPRESS_DB_PASSWORD gerada e salva no .env"
        fi
        if [ -z "$WORDPRESS_DB_ROOT_PASSWORD" ] || [ "$WORDPRESS_DB_ROOT_PASSWORD" = "change_this_root_password" ]; then
            WORDPRESS_DB_ROOT_PASSWORD=$(openssl rand -hex 24 2>/dev/null || head -c 24 /dev/urandom | xxd -p -c 256 2>/dev/null | head -c 48)
            _wp_upsert_env "WORDPRESS_DB_ROOT_PASSWORD" "$WORDPRESS_DB_ROOT_PASSWORD"
            print_info "WORDPRESS_DB_ROOT_PASSWORD gerada e salva no .env"
        fi
        WORDPRESS_VARS=("WORDPRESS_DB_NAME" "WORDPRESS_DB_USER" "WORDPRESS_DB_PASSWORD" "WORDPRESS_DB_ROOT_PASSWORD")
        for var in "${WORDPRESS_VARS[@]}"; do
            if [ -z "${!var}" ]; then
                print_error "Variável $var continua vazia após tentativa de preenchimento"
                print_info "Copie a secção WordPress de .env.example (linhas ~54–57) para o .env e defina valores reais."
                echo
                echo -e "${YELLOW}Exemplo (ajuste as passwords):${NC}"
                echo "  WORDPRESS_DB_NAME=wordpress"
                echo "  WORDPRESS_DB_USER=wordpress"
                echo "  WORDPRESS_DB_PASSWORD=..."
                echo "  WORDPRESS_DB_ROOT_PASSWORD=..."
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
        STACK_DESCRIPTION="n8n (Automação de Workflows)"

        # Verificar se a stack traefik está rodando
        if ! docker stack ls | grep -q "traefik"; then
            print_error "A stack Traefik precisa estar rodando antes do n8n"
            print_info "Execute primeiro o deploy do Traefik (opção 1)"
            exit 1
        fi

        # Gerar N8N_DB_PASSWORD se estiver vazio ou placeholder (antes da validação)
        if [ -z "$N8N_DB_PASSWORD" ] || [ "$N8N_DB_PASSWORD" = "change_this_secure_password" ]; then
            N8N_DB_PASSWORD=$(openssl rand -base64 24 2>/dev/null || head -c 32 /dev/urandom | base64 2>/dev/null)
            export N8N_DB_PASSWORD
            if grep -q "^N8N_DB_PASSWORD=" .env 2>/dev/null; then
                sed -i.bak "s|^N8N_DB_PASSWORD=.*|N8N_DB_PASSWORD=$N8N_DB_PASSWORD|" .env
            else
                echo "N8N_DB_PASSWORD=$N8N_DB_PASSWORD" >> .env
            fi
            print_info "N8N_DB_PASSWORD gerada e salva no .env"
        fi
        # Verificar variáveis n8n obrigatórias (incl. Postgres)
        N8N_VARS=("SUBDOMAIN_N8N" "N8N_ENCRYPTION_KEY" "N8N_DB_NAME" "N8N_DB_USER" "N8N_DB_PASSWORD")
        for var in "${N8N_VARS[@]}"; do
            if [ -z "${!var}" ]; then
                print_error "Variável $var não definida no .env"
                print_info "Configure SUBDOMAIN_N8N, N8N_ENCRYPTION_KEY e N8N_DB_* no arquivo .env"
                exit 1
            fi
        done

        # Criar diretório de dados do n8n (opcional; a stack usa volume nomeado)
        print_info "Criando diretório data/n8n (se necessário)..."
        mkdir -p data/n8n
        print_success "Diretórios verificados"
        ;;
    4)
        STACK_NAME="remotion"
        STACK_FILE="docker-stack-remotion.yml"
        STACK_DESCRIPTION="Remotion + MinIO (Studio + Render + Storage S3)"

        # Verificar se a stack traefik está rodando
        if ! docker stack ls | grep -q "traefik"; then
            print_error "A stack Traefik precisa estar rodando antes do Remotion"
            print_info "Execute primeiro o deploy do Traefik (opção 1)"
            exit 1
        fi

        # Upsert helper (reusa _upsert_env global)
        _remotion_upsert_env() { _upsert_env "$@"; }

        # Defaults de subdomínios
        if [ -z "$SUBDOMAIN_REMOTION" ]; then
            _remotion_upsert_env "SUBDOMAIN_REMOTION" "remotion"
            print_info "SUBDOMAIN_REMOTION definido (remotion) e gravado no .env"
        fi
        if [ -z "$SUBDOMAIN_MINIO" ]; then
            _remotion_upsert_env "SUBDOMAIN_MINIO" "minio"
            print_info "SUBDOMAIN_MINIO definido (minio) e gravado no .env"
        fi
        if [ -z "$SUBDOMAIN_S3" ]; then
            _remotion_upsert_env "SUBDOMAIN_S3" "s3"
            print_info "SUBDOMAIN_S3 definido (s3) e gravado no .env"
        fi
        if [ -z "$MINIO_ROOT_USER" ]; then
            _remotion_upsert_env "MINIO_ROOT_USER" "admin"
            print_info "MINIO_ROOT_USER definido (admin) e gravado no .env"
        fi
        if [ -z "$MINIO_ROOT_PASSWORD" ] || [ "$MINIO_ROOT_PASSWORD" = "change_this_strong_minio_password" ]; then
            MINIO_ROOT_PASSWORD=$(openssl rand -base64 24 2>/dev/null | tr -d '/+=' | head -c 32 || head -c 32 /dev/urandom | xxd -p -c 256 2>/dev/null | head -c 32)
            _remotion_upsert_env "MINIO_ROOT_PASSWORD" "$MINIO_ROOT_PASSWORD"
            print_info "MINIO_ROOT_PASSWORD gerada e salva no .env"
        fi
        if [ -z "$REMOTION_S3_BUCKET" ]; then
            _remotion_upsert_env "REMOTION_S3_BUCKET" "remotion"
            print_info "REMOTION_S3_BUCKET definido (remotion) e gravado no .env"
        fi

        # Validar vars obrigatórias
        REMOTION_VARS=("SUBDOMAIN_REMOTION" "SUBDOMAIN_MINIO" "SUBDOMAIN_S3" "MINIO_ROOT_USER" "MINIO_ROOT_PASSWORD" "REMOTION_S3_BUCKET")
        for var in "${REMOTION_VARS[@]}"; do
            if [ -z "${!var}" ]; then
                print_error "Variável $var continua vazia após tentativa de preenchimento"
                exit 1
            fi
        done

        # Nota: ensure_remotion_repo + ensure_remotion_image rodam no case Deploy (DEPLOY_OPTION=1).

        # Diretórios (futuro: logs locais; volume MinIO é nomeado)
        mkdir -p data/remotion
        print_success "Diretórios verificados"
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

        # Confirmar / solicitar DOMAIN (apenas se .env nao tiver um dominio valido)
        ensure_domain

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
        if [ "$STACK_NAME" = "traefik" ] && [ -z "$ACME_EMAIL" ]; then
            print_error "Variável ACME_EMAIL está vazia! Necessária para Let's Encrypt."
            print_info "Configure ACME_EMAIL no .env (ex.: ACME_EMAIL=admin@seudominio.com)"
            exit 1
        fi

        if [ "$STACK_NAME" = "traefik" ]; then
            ensure_traefik_stack_host_paths
        fi

        # Remotion precisa do projeto clonado e da imagem local antes do deploy
        if [ "$STACK_NAME" = "remotion" ]; then
            ensure_remotion_repo
            ensure_remotion_image
        fi

        # Deploy da stack (reimprime endpoint para o log deixar claro em qual daemon roda)
        print_header "Confirmacao do endpoint antes do deploy"
        show_docker_endpoint
        print_info "Comando: docker stack deploy -c ${STACK_FILE} --with-registry-auth ${STACK_NAME}"
        print_info "Fazendo deploy da stack '$STACK_NAME'..."
        docker stack deploy -c "$STACK_FILE" --with-registry-auth "$STACK_NAME"

        if ! docker stack ls --format '{{.Name}}' | grep -qx "$STACK_NAME"; then
            print_error "Stack '$STACK_NAME' nao aparece em 'docker stack ls' no endpoint atual."
            print_info "Verifique DOCKER_CONTEXT/DOCKER_HOST e se este eh o mesmo daemon onde Traefik/Portainer rodam."
            show_docker_endpoint
            exit 1
        fi
        print_success "Stack '$STACK_NAME' criada no daemon atual"

        # Aguardar serviços
        print_header "Aguardando Serviços"

        print_info "Aguardando serviços iniciarem (30s)..."
        sleep 30

        # Mostrar status
        echo
        docker stack services "$STACK_NAME"
        echo

        if docker stack services "$STACK_NAME" --format '{{.Replicas}}' | grep -q '^0/'; then
            print_warning "Algum servico esta com 0 replicas. Investigue com:"
            echo -e "  ${YELLOW}docker stack ps $STACK_NAME --no-trunc${NC}"
            echo
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
        elif [ "$STACK_NAME" = "n8n" ]; then
            echo -e "${BLUE}n8n (Automação de Workflows):${NC}"
            echo -e "  URL: ${YELLOW}https://${SUBDOMAIN_N8N:-n8n}.${DOMAIN}${NC}"
            echo -e "  ${YELLOW}Configure o usuário admin no primeiro acesso${NC}"
            echo
            print_warning "Certifique-se de que o DNS está configurado:"
            echo -e "  ${YELLOW}${SUBDOMAIN_N8N:-n8n}.${DOMAIN}${NC} → IP do servidor"
        elif [ "$STACK_NAME" = "remotion" ]; then
            echo -e "${BLUE}Remotion Studio:${NC}"
            echo -e "  URL: ${YELLOW}https://${SUBDOMAIN_REMOTION:-remotion}.${DOMAIN}${NC}"
            echo -e "  ${YELLOW}Protegido por BasicAuth (mesmo TRAEFIK_USER)${NC}"
            echo
            echo -e "${BLUE}Remotion Render API (interno, sem rota Traefik):${NC}"
            echo -e "  Endpoint: ${YELLOW}http://remotion-render:3000${NC} (via rede overlay 'remotion_internal')"
            echo -e "  Rotas: ${YELLOW}POST /renders${NC} e ${YELLOW}GET /renders/:id${NC}"
            echo
            echo -e "${BLUE}MinIO Console:${NC}"
            echo -e "  URL: ${YELLOW}https://${SUBDOMAIN_MINIO:-minio}.${DOMAIN}${NC}"
            echo -e "  Usuário: ${YELLOW}${MINIO_ROOT_USER}${NC}"
            echo -e "  Senha: ${YELLOW}(definida em MINIO_ROOT_PASSWORD no .env)${NC}"
            echo
            echo -e "${BLUE}MinIO API S3:${NC}"
            echo -e "  Endpoint: ${YELLOW}https://${SUBDOMAIN_S3:-s3}.${DOMAIN}${NC}"
            echo -e "  Bucket: ${YELLOW}${REMOTION_S3_BUCKET:-remotion}${NC}"
            echo
            print_warning "Certifique-se de que os DNS estão configurados:"
            echo -e "  ${YELLOW}${SUBDOMAIN_REMOTION:-remotion}.${DOMAIN}${NC} → IP do servidor"
            echo -e "  ${YELLOW}${SUBDOMAIN_MINIO:-minio}.${DOMAIN}${NC} → IP do servidor"
            echo -e "  ${YELLOW}${SUBDOMAIN_S3:-s3}.${DOMAIN}${NC} → IP do servidor"
            echo
            print_info "Para integrar o n8n com a API de render:"
            echo -e "  ${YELLOW}docker network connect remotion_internal \$(docker ps -qf name=n8n_n8n | head -1)${NC}"
            echo -e "  No n8n: HTTP Request → POST http://remotion-render:3000/renders"
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
        elif [ "$STACK_NAME" = "n8n" ]; then
            SERVICE="n8n"
        elif [ "$STACK_NAME" = "remotion" ]; then
            echo -e "${YELLOW}Escolha o serviço:${NC}"
            echo "1) Remotion Studio"
            echo "2) Remotion Render (API)"
            echo "3) MinIO"
            echo "4) MinIO Setup (bucket init)"
            echo
            read -p "Opção [1]: " SERVICE_OPTION
            SERVICE_OPTION=${SERVICE_OPTION:-1}

            case $SERVICE_OPTION in
                1) SERVICE="remotion-studio" ;;
                2) SERVICE="remotion-render" ;;
                3) SERVICE="minio" ;;
                4) SERVICE="minio-setup" ;;
                *) SERVICE="remotion-studio" ;;
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
        elif [ "$STACK_NAME" = "n8n" ]; then
            echo "  - Remover os volumes n8n_n8n_data e n8n_postgres_data (workflows e banco Postgres)"
        elif [ "$STACK_NAME" = "remotion" ]; then
            echo "  - Remover o volume remotion_minio_data (todos os MP4s armazenados no MinIO)"
            echo "  - Opcionalmente remover ./remotion (projeto clonado) e a imagem remotion-local:latest"
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
            elif [ "$STACK_NAME" = "n8n" ]; then
                docker volume rm n8n_n8n_data n8n_postgres_data 2>/dev/null || true
            elif [ "$STACK_NAME" = "remotion" ]; then
                docker volume rm remotion_minio_data 2>/dev/null || true
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
            elif [ "$STACK_NAME" = "wordpress" ]; then
                print_warning "Remover dados locais em ./data/wordpress e ./backups/wordpress?"
                read -p "Digite 'SIM' para confirmar: " CONFIRM_DATA
                if [ "$CONFIRM_DATA" = "SIM" ]; then
                    rm -rf data/wordpress/* backups/wordpress/*
                    print_success "Dados locais removidos"
                fi
            elif [ "$STACK_NAME" = "n8n" ]; then
                print_warning "Remover dados locais em ./data/n8n?"
                read -p "Digite 'SIM' para confirmar: " CONFIRM_DATA
                if [ "$CONFIRM_DATA" = "SIM" ]; then
                    rm -rf data/n8n/*
                    print_success "Dados locais removidos"
                fi
            elif [ "$STACK_NAME" = "remotion" ]; then
                print_warning "Remover pasta ./remotion (projeto clonado do template)?"
                read -p "Digite 'SIM' para confirmar: " CONFIRM_DATA
                if [ "$CONFIRM_DATA" = "SIM" ]; then
                    rm -rf remotion
                    print_success "Pasta ./remotion removida"
                fi
                print_warning "Remover imagem local 'remotion-local:latest'?"
                read -p "Digite 'SIM' para confirmar: " CONFIRM_IMG
                if [ "$CONFIRM_IMG" = "SIM" ]; then
                    docker image rm remotion-local:latest 2>/dev/null && print_success "Imagem removida" || print_warning "Imagem não encontrada"
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
if [ "$STACK_NAME" = "n8n" ]; then
    echo "  Logs n8n: ${YELLOW}docker service logs -f ${STACK_NAME}_n8n${NC}"
elif [ "$STACK_NAME" = "remotion" ]; then
    echo "  Logs Studio:  ${YELLOW}docker service logs -f ${STACK_NAME}_remotion-studio${NC}"
    echo "  Logs Render:  ${YELLOW}docker service logs -f ${STACK_NAME}_remotion-render${NC}"
    echo "  Logs MinIO:   ${YELLOW}docker service logs -f ${STACK_NAME}_minio${NC}"
    echo "  Rebuild img:  ${YELLOW}docker build -t remotion-local:latest ./remotion${NC}"
    echo "  Update stack: ${YELLOW}docker service update --force ${STACK_NAME}_remotion-studio${NC}"
else
    echo "  Ver logs: ${YELLOW}docker service logs -f ${STACK_NAME}_traefik${NC}"
    echo "  Escalar serviço: ${YELLOW}docker service scale ${STACK_NAME}_portainer=2${NC}"
    echo "  Atualizar serviço: ${YELLOW}docker service update ${STACK_NAME}_traefik${NC}"
fi
echo
