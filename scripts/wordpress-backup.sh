#!/bin/bash

# WordPress Backup Script
# Backs up MySQL database and wp-content directory

set -e

# Configurações
BACKUP_DIR="/backups"
DATE=$(date +%Y%m%d_%H%M%S)
MYSQL_BACKUP="${BACKUP_DIR}/mysql/wordpress_${DATE}.sql.gz"
FILES_BACKUP="${BACKUP_DIR}/files/wordpress_files_${DATE}.tar.gz"
RETENTION_DAYS=7

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Banner
echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   WordPress Backup Script              ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
echo ""

# Verificar variáveis de ambiente
if [ -z "$MYSQL_HOST" ] || [ -z "$MYSQL_DATABASE" ] || [ -z "$MYSQL_USER" ] || [ -z "$MYSQL_PASSWORD" ]; then
    print_error "Variáveis de ambiente não configuradas"
    exit 1
fi

# Criar diretórios de backup
mkdir -p "${BACKUP_DIR}/mysql"
mkdir -p "${BACKUP_DIR}/files"

# Backup do MySQL
print_info "Iniciando backup do banco de dados..."
if mysqldump -h"$MYSQL_HOST" -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" | gzip > "$MYSQL_BACKUP"; then
    print_success "Backup do MySQL concluído: $(basename $MYSQL_BACKUP)"
    print_info "Tamanho: $(du -h $MYSQL_BACKUP | cut -f1)"
else
    print_error "Falha no backup do MySQL"
    exit 1
fi

# Backup dos arquivos wp-content
print_info "Iniciando backup dos arquivos..."
if tar -czf "$FILES_BACKUP" -C /var/www/html wp-content 2>/dev/null; then
    print_success "Backup dos arquivos concluído: $(basename $FILES_BACKUP)"
    print_info "Tamanho: $(du -h $FILES_BACKUP | cut -f1)"
else
    print_error "Falha no backup dos arquivos"
    exit 1
fi

# Limpeza de backups antigos
print_info "Limpando backups antigos (mais de ${RETENTION_DAYS} dias)..."
DELETED=0

# Limpar backups MySQL antigos
find "${BACKUP_DIR}/mysql" -name "wordpress_*.sql.gz" -type f -mtime +${RETENTION_DAYS} -delete 2>/dev/null && DELETED=$((DELETED + $(find "${BACKUP_DIR}/mysql" -name "wordpress_*.sql.gz" -type f -mtime +${RETENTION_DAYS} | wc -l)))

# Limpar backups de arquivos antigos
find "${BACKUP_DIR}/files" -name "wordpress_files_*.tar.gz" -type f -mtime +${RETENTION_DAYS} -delete 2>/dev/null && DELETED=$((DELETED + $(find "${BACKUP_DIR}/files" -name "wordpress_files_*.tar.gz" -type f -mtime +${RETENTION_DAYS} | wc -l)))

if [ $DELETED -gt 0 ]; then
    print_success "Removidos $DELETED backups antigos"
else
    print_info "Nenhum backup antigo para remover"
fi

# Resumo
echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Backup Concluído com Sucesso         ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
print_info "Backups disponíveis:"
echo -e "  MySQL: ${YELLOW}$(ls -1 ${BACKUP_DIR}/mysql | wc -l)${NC} arquivo(s)"
echo -e "  Arquivos: ${YELLOW}$(ls -1 ${BACKUP_DIR}/files | wc -l)${NC} arquivo(s)"
echo ""
