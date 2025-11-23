#!/bin/bash

# Script de Diagnóstico SSL
# Verifica problemas com certificados Let's Encrypt via Cloudflare

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

clear
echo -e "${BLUE}"
cat << "EOF"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   Diagnóstico de Problemas SSL                           ║
║   Traefik + Let's Encrypt + Cloudflare                   ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

# 1. Verificar containers
print_header "1. Verificando Containers"

if docker ps | grep -q traefik; then
    print_success "Traefik está rodando"
    docker ps --filter "name=traefik" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
else
    print_error "Traefik NÃO está rodando"
    echo
    print_info "Inicie o Traefik primeiro:"
    echo "  Docker Compose: docker-compose up -d"
    echo "  Docker Swarm: ./swarm-deploy.sh"
    exit 1
fi

echo

# 2. Verificar arquivo .env
print_header "2. Verificando Configuração (.env)"

if [ ! -f .env ]; then
    print_error "Arquivo .env não encontrado!"
    exit 1
fi

source .env

# Verificar variáveis críticas
echo -e "${YELLOW}Variáveis configuradas:${NC}"
echo "  DOMAIN: ${DOMAIN:-NÃO DEFINIDO}"
echo "  SUBDOMAIN_TRAEFIK: ${SUBDOMAIN_TRAEFIK:-NÃO DEFINIDO}"
echo "  SUBDOMAIN_PORTAINER: ${SUBDOMAIN_PORTAINER:-NÃO DEFINIDO}"
echo "  ACME_EMAIL: ${ACME_EMAIL:-NÃO DEFINIDO}"
echo "  CF_API_EMAIL: ${CF_API_EMAIL:-NÃO DEFINIDO}"

if [ -z "$CF_API_KEY" ]; then
    echo "  CF_API_KEY: ${RED}NÃO DEFINIDO${NC}"
    print_error "CF_API_KEY não está configurado!"
else
    echo "  CF_API_KEY: ${GREEN}Configurado (${#CF_API_KEY} caracteres)${NC}"
fi

if [ -z "$CF_DNS_API_TOKEN" ]; then
    echo "  CF_DNS_API_TOKEN: ${YELLOW}NÃO DEFINIDO${NC}"
    print_warning "CF_DNS_API_TOKEN não está configurado (opcional se CF_API_KEY estiver configurado)"
else
    echo "  CF_DNS_API_TOKEN: ${GREEN}Configurado (${#CF_DNS_API_TOKEN} caracteres)${NC}"
fi

echo

# 3. Verificar DNS
print_header "3. Verificando DNS"

TRAEFIK_DOMAIN="${SUBDOMAIN_TRAEFIK:-pr}.${DOMAIN}"
PORTAINER_DOMAIN="${SUBDOMAIN_PORTAINER:-painel}.${DOMAIN}"

echo -e "${YELLOW}Testando resolução DNS:${NC}"
echo

# Traefik
echo -n "  $TRAEFIK_DOMAIN: "
TRAEFIK_IP=$(dig +short "$TRAEFIK_DOMAIN" @8.8.8.8 | tail -1)
if [ -n "$TRAEFIK_IP" ]; then
    echo -e "${GREEN}$TRAEFIK_IP${NC}"
else
    echo -e "${RED}NÃO RESOLVE${NC}"
    print_error "DNS não configurado para $TRAEFIK_DOMAIN"
fi

# Portainer
echo -n "  $PORTAINER_DOMAIN: "
PORTAINER_IP=$(dig +short "$PORTAINER_DOMAIN" @8.8.8.8 | tail -1)
if [ -n "$PORTAINER_IP" ]; then
    echo -e "${GREEN}$PORTAINER_IP${NC}"
else
    echo -e "${RED}NÃO RESOLVE${NC}"
    print_error "DNS não configurado para $PORTAINER_DOMAIN"
fi

echo

# 4. Verificar acme.json
print_header "4. Verificando Certificados (acme.json)"

ACME_FILE="data/traefik/acme.json"

if [ ! -f "$ACME_FILE" ]; then
    print_error "Arquivo $ACME_FILE não encontrado!"
else
    ACME_SIZE=$(stat -f%z "$ACME_FILE" 2>/dev/null || stat -c%s "$ACME_FILE" 2>/dev/null)
    ACME_PERMS=$(stat -f%A "$ACME_FILE" 2>/dev/null || stat -c%a "$ACME_FILE" 2>/dev/null)

    echo "  Tamanho: $ACME_SIZE bytes"
    echo "  Permissões: $ACME_PERMS"

    if [ "$ACME_PERMS" != "600" ]; then
        print_warning "Permissões incorretas! Deve ser 600"
        print_info "Corrija com: chmod 600 $ACME_FILE"
    else
        print_success "Permissões corretas (600)"
    fi

    if [ "$ACME_SIZE" -lt 50 ]; then
        print_warning "Arquivo muito pequeno - provavelmente vazio"
        print_info "Certificados ainda não foram gerados"
    else
        print_success "Certificados parecem estar presentes"

        # Tentar mostrar domínios nos certificados
        if command -v jq &> /dev/null; then
            echo
            echo -e "${YELLOW}Certificados encontrados:${NC}"
            jq -r '.cloudflare.Certificates[]?.domain.main // empty' "$ACME_FILE" 2>/dev/null | while read domain; do
                echo "  - $domain"
            done
        fi
    fi
fi

echo

# 5. Logs do Traefik
print_header "5. Logs do Traefik (últimas 50 linhas)"

echo -e "${YELLOW}Procurando por erros...${NC}"
echo

# Detectar se é Compose ou Swarm
if docker ps --format '{{.Names}}' | grep -q "traefik_traefik"; then
    # Swarm
    LOGS=$(docker service logs traefik_traefik --tail 50 2>&1)
else
    # Compose
    LOGS=$(docker logs traefik --tail 50 2>&1)
fi

# Filtrar erros relevantes
echo "$LOGS" | grep -i "error\|fail\|cloudflare\|acme\|certificate" || echo "  Nenhum erro óbvio encontrado nos logs recentes"

echo

# 6. Verificar conectividade Cloudflare API
print_header "6. Testando Conectividade com Cloudflare API"

if [ -n "$CF_API_KEY" ] && [ -n "$CF_API_EMAIL" ]; then
    echo "Testando autenticação com Cloudflare..."

    API_TEST=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "X-Auth-Email: $CF_API_EMAIL" \
        -H "X-Auth-Key: $CF_API_KEY" \
        -H "Content-Type: application/json")

    if echo "$API_TEST" | grep -q '"success":true'; then
        print_success "Autenticação com Cloudflare OK"
    else
        print_error "Falha na autenticação com Cloudflare"
        echo "$API_TEST" | jq '.' 2>/dev/null || echo "$API_TEST"
    fi
elif [ -n "$CF_DNS_API_TOKEN" ]; then
    echo "Testando token DNS da Cloudflare..."

    API_TEST=$(curl -s -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
        -H "Authorization: Bearer $CF_DNS_API_TOKEN" \
        -H "Content-Type: application/json")

    if echo "$API_TEST" | grep -q '"success":true'; then
        print_success "Token DNS da Cloudflare OK"
    else
        print_error "Falha na validação do token DNS"
        echo "$API_TEST" | jq '.' 2>/dev/null || echo "$API_TEST"
    fi
else
    print_error "Nenhuma credencial da Cloudflare configurada"
fi

echo

# 7. Resumo e Recomendações
print_header "7. Resumo e Recomendações"

echo -e "${YELLOW}Checklist:${NC}"
echo

# Containers
if docker ps | grep -q traefik; then
    echo -e "  ${GREEN}✓${NC} Traefik rodando"
else
    echo -e "  ${RED}✗${NC} Traefik NÃO está rodando"
fi

# DNS
if [ -n "$TRAEFIK_IP" ]; then
    echo -e "  ${GREEN}✓${NC} DNS configurado para $TRAEFIK_DOMAIN"
else
    echo -e "  ${RED}✗${NC} DNS NÃO configurado para $TRAEFIK_DOMAIN"
fi

# Credenciais
if [ -n "$CF_API_KEY" ] || [ -n "$CF_DNS_API_TOKEN" ]; then
    echo -e "  ${GREEN}✓${NC} Credenciais Cloudflare configuradas"
else
    echo -e "  ${RED}✗${NC} Credenciais Cloudflare NÃO configuradas"
fi

# acme.json
if [ -f "$ACME_FILE" ] && [ "$ACME_PERMS" = "600" ]; then
    echo -e "  ${GREEN}✓${NC} Arquivo acme.json configurado corretamente"
else
    echo -e "  ${RED}✗${NC} Problema com arquivo acme.json"
fi

echo
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo

# Recomendações específicas
if [ -z "$TRAEFIK_IP" ]; then
    print_error "PROBLEMA: DNS não está configurado!"
    echo
    echo "Configure no Cloudflare:"
    echo "  Tipo: A"
    echo "  Nome: $SUBDOMAIN_TRAEFIK"
    echo "  Conteúdo: <IP_DO_SERVIDOR>"
    echo "  Proxy: Desabilitado (somente DNS)"
    echo
fi

if [ "$ACME_SIZE" -lt 50 ]; then
    print_warning "Certificados ainda não foram gerados"
    echo
    echo "Forçar regeneração dos certificados:"
    echo "  1. Pare o Traefik: docker-compose down"
    echo "  2. Remova o acme.json: rm $ACME_FILE && touch $ACME_FILE && chmod 600 $ACME_FILE"
    echo "  3. Reinicie: docker-compose up -d"
    echo "  4. Aguarde 2-3 minutos"
    echo "  5. Verifique os logs: docker logs traefik -f"
    echo
fi

print_info "Para ver logs em tempo real:"
echo "  docker logs traefik -f"
echo
