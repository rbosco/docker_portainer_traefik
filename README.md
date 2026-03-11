# Docker Stack: Traefik 2.10.7 + Portainer

Estrutura completa para gerenciamento de containers Docker usando Traefik como reverse proxy e Portainer como interface de gerenciamento.

## ⚠️ Requisitos Importantes

### Docker 24.0.7 (API 1.43)

Este projeto requer **Docker 24.0.7** para funcionar corretamente com o Traefik 2.10.7.

**Versões incompatíveis:**
- ❌ Docker 29.x (API 1.52) - Incompatível
- ❌ Docker 28.x (API 1.45+) - Problemas de compatibilidade
- ✅ **Docker 24.0.7 (API 1.43)** - Testado e funcionando

**📖 [Guia completo de instalação do Docker 24.0.7 →](INSTALL-DOCKER.md)**

Se você já tem Docker instalado, verifique a versão:
```bash
docker version --format '{{.Server.Version}}'
# Deve mostrar: 24.0.7
```

## 📋 Componentes

- **Traefik 2.10.7**: Reverse proxy moderno com suporte a Let's Encrypt (compatível com Docker 24.0.7)
- **Portainer CE**: Interface web para gerenciamento de containers Docker
- **Docker Compose**: Orquestração dos serviços
- **Docker Swarm** (opcional): Suporte completo para clusters e alta disponibilidade

## 🐝 Docker Swarm

Este projeto inclui **suporte completo para Docker Swarm**!

**Características:**
- ✅ Alta disponibilidade com múltiplos nodes
- ✅ Load balancing automático
- ✅ Rolling updates sem downtime
- ✅ Escalabilidade horizontal
- ✅ Failover automático

**Arquivos para Swarm:**
- `docker-stack.yml` - Stack otimizada para Swarm
- `swarm-init.sh` - Script de inicialização do cluster
- `swarm-deploy.sh` - Script de deploy e gerenciamento
- `README-SWARM.md` - **[Documentação completa do Swarm](README-SWARM.md)** 📖

**URLs customizadas:**
- Traefik Dashboard: `https://pr.seudominio.com`
- Portainer: `https://painel.seudominio.com`

**Início rápido com Swarm:**
```bash
# 1. Inicializar Swarm
./swarm-init.sh

# 2. Configurar .env
cp .env.example .env
nano .env

# 3. Deploy da stack
./swarm-deploy.sh
```

📚 **[Leia a documentação completa do Swarm →](README-SWARM.md)**

## 🏗️ Estrutura do Projeto

```
.
├── docker-compose.yml          # Docker Compose (single node)
├── docker-compose-n8n.yml      # n8n local (testes com Docker Compose)
├── docker-stack.yml            # Docker Swarm Stack (cluster)
├── setup.sh                    # Script de instalação automática (Compose)
├── swarm-init.sh              # Script de inicialização do Swarm
├── swarm-deploy.sh            # Script de deploy da Stack
├── .env                        # Variáveis de ambiente (não versionado)
├── .env.example               # Exemplo de variáveis de ambiente
├── .gitignore                 # Arquivos ignorados pelo Git
├── README.md                  # Documentação principal
├── README-SWARM.md            # Documentação Docker Swarm
├── traefik/
│   ├── traefik.yml           # Configuração Traefik (Compose)
│   ├── traefik-swarm.yml     # Configuração Traefik (Swarm)
│   └── dynamic/
│       └── tls.yml           # Configuração TLS dinâmica
└── data/                      # Dados persistentes (não versionado)
    ├── traefik/
    │   └── acme.json         # Certificados Let's Encrypt
    └── portainer/            # Dados do Portainer
```

## 🎯 Modos de Instalação

Este projeto suporta **dois modos de instalação**:

### 📦 Docker Compose (Recomendado para iniciantes)

**Quando usar:**
- ✅ Servidor único
- ✅ Desenvolvimento e testes
- ✅ Projetos pequenos/médios
- ✅ Budget limitado
- ✅ Simplicidade

**Arquivos:**
- `docker-compose.yml`
- `setup.sh`

**Comandos:**
```bash
./setup.sh                    # Instalação automática
# ou
docker compose up -d          # Manual
```

**Testar n8n localmente (Docker Compose):**
```bash
# Rede proxy (uma vez, se não existir)
docker network create proxy 2>/dev/null || true

# Subir n8n (acesso em http://localhost:5678)
docker compose -f docker-compose-n8n.yml up -d

# Com Traefik no ar: subir a base primeiro, depois n8n (também acessível pelo subdomínio)
docker compose up -d && docker compose -f docker-compose-n8n.yml up -d
```
Use `.env` com `SUBDOMAIN_N8N` e `N8N_ENCRYPTION_KEY`; para teste rápido sem `.env`, o compose usa valores padrão.

### 🐝 Docker Swarm (Recomendado para produção)

**Quando usar:**
- ✅ Múltiplos servidores (cluster)
- ✅ Alta disponibilidade necessária
- ✅ Produção enterprise
- ✅ Escalabilidade automática
- ✅ Zero downtime crítico

**Arquivos:**
- `docker-stack.yml`
- `swarm-init.sh`
- `swarm-deploy.sh`

**Comandos:**
```bash
./swarm-init.sh              # Inicializar cluster
./swarm-deploy.sh            # Deploy da stack
```

**URLs:**
- Traefik Dashboard: `pr.seudominio.com` (ou `pr.localhost` em dev)
- Portainer: `painel.seudominio.com` (ou `painel.localhost` em dev)
- **Nota:** URLs unificadas para ambos os modos!

### 📊 Comparação Rápida

| Característica | Compose | Swarm |
|----------------|---------|-------|
| Servidores | 1 | 1+ (cluster) |
| Alta Disponibilidade | ❌ | ✅ |
| Load Balancing | ❌ | ✅ Automático |
| Escalabilidade | Manual | Automática |
| Complexidade | 🟢 Simples | 🟡 Média |
| Custo | 💰 Baixo | 💰💰 Médio |
| Ideal para | Dev/Small | Produção |

## 🚀 Início Rápido

### Pré-requisitos

- Docker Engine 20.10+
- Docker Compose 2.0+
- Porta 80, 443 e 8080 disponíveis

### Instalação Automática (Recomendado)

O script `setup.sh` configura tudo automaticamente de forma interativa:

1. **Clone o repositório:**
```bash
git clone <repository-url>
cd docker_portainer_traefik
```

2. **Execute o script de instalação:**
```bash
chmod +x setup.sh
./setup.sh
```

O script irá:
- ✅ Verificar todos os pré-requisitos (Docker, Docker Compose, portas)
- ✅ Coletar informações de configuração (domínio, credenciais, etc.)
- ✅ Escolher entre modo Desenvolvimento ou Produção
- ✅ Gerar automaticamente o arquivo `.env`
- ✅ Configurar permissões e estrutura de diretórios
- ✅ Iniciar todos os serviços
- ✅ Exibir informações de acesso

### Instalação Manual

Se preferir configurar manualmente:

1. **Clone o repositório:**
```bash
git clone <repository-url>
cd docker_portainer_traefik
```

2. **Configure as variáveis de ambiente:**
```bash
cp .env.example .env
nano .env
```

Edite as seguintes variáveis no arquivo `.env`:
- `DOMAIN`: Seu domínio (ex: example.com)
- `TZ`: Seu timezone
- `TRAEFIK_USER`: Credenciais para o dashboard do Traefik
- `CF_API_EMAIL` e `CF_API_KEY`: Credenciais Cloudflare (se usar Let's Encrypt)

3. **Prepare os arquivos necessários:**
```bash
mkdir -p data/traefik data/portainer
touch data/traefik/acme.json
chmod 600 data/traefik/acme.json
```

4. **Inicie os serviços:**
```bash
docker-compose up -d
```

5. **Verifique o status:**
```bash
docker-compose ps
docker-compose logs -f
```

## 🔐 Acesso aos Serviços

### URLs Unificadas (Compose e Swarm)

**Desenvolvimento Local (sem domínio):**

- **Traefik Dashboard**:
  - Via proxy: http://pr.localhost
  - Direto: http://localhost:8080
  - Usuário padrão: `admin` / Senha: `admin`

- **Portainer**:
  - Via proxy: http://painel.localhost
  - Direto: http://localhost:9000
  - Configure o usuário admin no primeiro acesso

**Produção (com domínio configurado):**

- **Traefik Dashboard**: https://pr.seudominio.com
  - Autenticação configurada via `TRAEFIK_USER`
  - Monitoramento e métricas em tempo real
  - Dashboard interativo do Traefik

- **Portainer**: https://painel.seudominio.com
  - Gerenciamento de containers/cluster
  - Deploy via interface web
  - Visualização de logs e métricas
  - **Swarm:** Gerenciamento completo de nodes

**Configuração DNS necessária:**
```
A    pr        SEU_IP_SERVIDOR
A    painel    SEU_IP_SERVIDOR

# Ou com wildcard:
A    *         SEU_IP_SERVIDOR
```

## ⚙️ Configuração

### Personalizar Subdomínios

Você pode customizar os subdomínios dos serviços editando o arquivo `.env`:

```bash
# Subdomínios padrão
SUBDOMAIN_TRAEFIK=pr
SUBDOMAIN_PORTAINER=painel
```

**Exemplos de customização:**

```bash
# Usar subdomínios tradicionais
SUBDOMAIN_TRAEFIK=traefik
SUBDOMAIN_PORTAINER=portainer

# Usar nomes personalizados
SUBDOMAIN_TRAEFIK=dashboard
SUBDOMAIN_PORTAINER=admin

# Usar nomes curtos
SUBDOMAIN_TRAEFIK=t
SUBDOMAIN_PORTAINER=p
```

Após alterar, reinicie os serviços:

```bash
# Docker Compose
docker compose down && docker compose up -d

# Docker Swarm
./swarm-deploy.sh
```

**Importante:** Atualize seus registros DNS para os novos subdomínios!

### Traefik Dashboard - Alterar Senha

Para gerar um novo hash de senha para o Traefik:

```bash
# Instale o htpasswd se necessário
sudo apt-get install apache2-utils

# Gere o hash
echo $(htpasswd -nb admin sua_senha) | sed -e s/\\$/\\$\\$/g
```

Copie o resultado e atualize a variável `TRAEFIK_USER` no arquivo `.env`.

### Let's Encrypt com Cloudflare

1. Obtenha suas credenciais Cloudflare:
   - API Email: seu email da conta Cloudflare
   - API Key: Global API Key ou API Token com permissões DNS

2. Atualize o arquivo `traefik/traefik.yml`:
```yaml
certificatesResolvers:
  cloudflare:
    acme:
      email: seu-email@example.com  # Atualize aqui
      storage: acme.json
      dnsChallenge:
        provider: cloudflare
```

3. Adicione as variáveis de ambiente ao docker-compose.yml (seção environment do Traefik):
```yaml
environment:
  - CF_API_EMAIL=${CF_API_EMAIL}
  - CF_API_KEY=${CF_API_KEY}
```

### Adicionar Novos Serviços

Para adicionar um novo serviço ao Traefik, use labels no docker-compose:

```yaml
services:
  meu-app:
    image: minha-imagem
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.meu-app.rule=Host(`app.${DOMAIN}`)"
      - "traefik.http.routers.meu-app.entrypoints=https"
      - "traefik.http.routers.meu-app.tls=true"
      - "traefik.http.routers.meu-app.tls.certresolver=cloudflare"
      - "traefik.http.services.meu-app.loadbalancer.server.port=8000"

networks:
  proxy:
    external: true
```

## 🔄 Migração: Compose → Swarm

Já está usando Docker Compose e quer migrar para Swarm? Siga este guia:

### Passo 1: Backup dos Dados

```bash
# Fazer backup dos volumes do Portainer
docker run --rm \
  -v docker_portainer_traefik_portainer-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/portainer-backup.tar.gz /data

# Backup dos certificados (se existirem)
cp -r data/traefik data/traefik.backup
```

### Passo 2: Parar Serviços Compose

```bash
docker compose down
```

### Passo 3: Atualizar .env

Adicione as variáveis necessárias para Swarm:

```bash
# Adicione ao .env
ACME_EMAIL=seu-email@example.com
STACK_NAME=traefik
```

### Passo 4: Inicializar Swarm

```bash
./swarm-init.sh
```

Escolha a opção **1** (Manager - primeiro node)

### Passo 5: Restaurar Dados (Opcional)

```bash
# Se tiver backup do Portainer, restaure:
docker run --rm \
  -v traefik_portainer-data:/data \
  -v $(pwd):/backup \
  alpine sh -c "cd / && tar xzf /backup/portainer-backup.tar.gz"
```

### Passo 6: Deploy no Swarm

```bash
./swarm-deploy.sh
```

Escolha a opção **1** (Deploy/Atualizar stack)

### Passo 7: Verificar DNS

Os subdomínios já estão unificados! Certifique-se de que seus registros DNS estão configurados:

```
A    pr       SEU_IP_SERVIDOR
A    painel   SEU_IP_SERVIDOR
```

**Nota:** As URLs são as mesmas para Compose e Swarm desde a última atualização.

### Diferenças Importantes

| Aspecto | Compose | Swarm |
|---------|---------|-------|
| Comando de deploy | `docker compose up -d` | `docker stack deploy` |
| Ver serviços | `docker compose ps` | `docker stack services traefik` |
| Ver logs | `docker compose logs -f` | `docker service logs -f traefik_traefik` |
| Escalar | Editar compose + redeploy | `docker service scale traefik_app=3` |
| Rede | bridge | overlay |
| Volumes | bind mounts funcionam | Preferir volumes nomeados |

### Verificação Pós-Migração

```bash
# Verificar nodes do cluster
docker node ls

# Verificar serviços
docker stack services traefik

# Verificar logs
docker service logs -f traefik_traefik
docker service logs -f traefik_portainer

# Acessar dashboard
curl -I https://pr.seudominio.com
curl -I https://painel.seudominio.com
```

## 🔧 Comandos Úteis

### Docker Compose

```bash
# Iniciar serviços
docker compose up -d

# Parar serviços
docker compose down

# Reiniciar serviços
docker compose restart

# Ver status
docker compose ps

# Ver logs
docker compose logs -f

# Ver logs de um serviço específico
docker compose logs -f traefik
docker compose logs -f portainer

# Atualizar imagens
docker compose pull
docker compose up -d

# Validar configuração
docker compose config
```

### Docker Swarm

```bash
# Deploy da stack
./swarm-deploy.sh
# ou
docker stack deploy -c docker-stack.yml traefik

# Ver serviços
docker stack services traefik

# Ver containers (tasks)
docker stack ps traefik

# Ver logs
docker service logs -f traefik_traefik
docker service logs -f traefik_portainer

# Escalar serviço
docker service scale traefik_portainer=3

# Atualizar serviço
docker service update --image traefik:2.11.4 traefik_traefik

# Rollback de atualização
docker service rollback traefik_traefik

# Remover stack
docker stack rm traefik

# Ver nodes do cluster
docker node ls

# Inspecionar node
docker node inspect <node-id>

# Drenar node (mover containers)
docker node update --availability drain <node-id>

# Reativar node
docker node update --availability active <node-id>
```

### Manutenção

```bash
# Limpar containers não utilizados
docker system prune -a

# Backup dos dados do Portainer (Compose)
tar -czf portainer-backup-$(date +%Y%m%d).tar.gz data/portainer/

# Backup dos dados do Portainer (Swarm)
docker run --rm \
  -v traefik_portainer-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/portainer-backup-$(date +%Y%m%d).tar.gz /data

# Verificar rede
docker network inspect proxy

# Ver uso de recursos
docker stats

# Ver eventos em tempo real
docker events --filter type=service
```

## 🛡️ Segurança

### Boas Práticas Implementadas

- ✅ Uso de `no-new-privileges:true` nos containers
- ✅ Dashboard do Traefik protegido com autenticação básica
- ✅ Redirecionamento automático HTTP → HTTPS
- ✅ TLS 1.2+ com cipher suites seguros
- ✅ Docker socket como read-only
- ✅ Rede isolada para comunicação entre containers

### Recomendações Adicionais

1. **Altere as senhas padrão** no arquivo `.env`
2. **Configure firewall** para permitir apenas portas necessárias
3. **Mantenha os serviços atualizados** regularmente
4. **Faça backups periódicos** dos dados
5. **Use certificados válidos** em produção (Let's Encrypt)

## 🐛 Troubleshooting

### Porta já em uso

```bash
# Verificar qual processo está usando a porta
sudo lsof -i :80
sudo lsof -i :443

# Parar o processo se necessário
sudo systemctl stop apache2  # ou nginx
```

### Erro de rede "network proxy has incorrect label"

Se você receber o erro:
```
WARN network proxy was found but has incorrect label com.docker.compose.network
```

**Solução:**
```bash
# Parar todos os containers
docker compose down

# Remover a rede antiga (se não estiver em uso)
docker network rm proxy

# Recriar tudo
docker compose up -d
```

Se a rede estiver em uso por outros containers:
```bash
# Verificar quais containers estão usando a rede
docker network inspect proxy

# Parar os containers que estão usando
docker stop <container-id>

# Remover a rede
docker network rm proxy

# Iniciar novamente
docker compose up -d
```

### Certificados Let's Encrypt não são gerados

1. Verifique se as credenciais Cloudflare estão corretas
2. Verifique os logs do Traefik:
```bash
docker-compose logs traefik | grep -i acme
```
3. Certifique-se de que o domínio está apontando para o servidor

### Dashboard do Traefik não acessível

1. Verifique se o container está rodando:
```bash
docker-compose ps
```

2. Verifique os logs:
```bash
docker-compose logs traefik
```

3. Teste o acesso direto à porta:
```bash
curl -I http://localhost:8080
```

## 📚 Documentação

- [Traefik Documentation](https://doc.traefik.io/traefik/)
- [Portainer Documentation](https://docs.portainer.io/)
- [Docker Compose Documentation](https://docs.docker.com/compose/)

## 📄 Licença

Este projeto é disponibilizado sob a licença MIT.

## 🤝 Contribuindo

Contribuições são bem-vindas! Sinta-se à vontade para abrir issues e pull requests.
