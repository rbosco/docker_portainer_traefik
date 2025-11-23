# Docker Swarm: Traefik 2.11.3 + Portainer

Guia completo para deploy da stack Traefik + Portainer em **Docker Swarm**.

## 🐝 Visão Geral

Esta configuração utiliza Docker Swarm para orquestração de containers com:

- **Traefik 2.11.3**: Reverse proxy com load balancing automático
- **Portainer CE**: Interface de gerenciamento do Swarm
- **Portainer Agent**: Agente para coleta de informações dos nodes
- **Alta Disponibilidade**: Múltiplas réplicas e failover automático
- **Escalabilidade**: Escale serviços com um comando
- **Zero Downtime**: Rolling updates automáticos

## 🌐 URLs dos Serviços

- **Traefik Dashboard**: `https://pr.seudominio.com`
- **Portainer**: `https://painel.seudominio.com`

## 📋 Pré-requisitos

### Hardware Mínimo Recomendado

**Para ambiente de produção:**

```
Manager Nodes (mínimo 3):
- 2 CPU cores
- 4 GB RAM
- 20 GB SSD
- Rede de 1 Gbps

Worker Nodes (conforme necessidade):
- 2 CPU cores
- 4 GB RAM
- 20 GB SSD
- Rede de 1 Gbps
```

**Para testes (node único):**
```
- 2 CPU cores
- 2 GB RAM
- 10 GB SSD
```

### Software

- Docker Engine 20.10+
- Docker CLI com suporte a Swarm
- Sistema operacional Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+)
- Portas abertas: 80, 443, 2377, 7946, 4789

## 🔧 Portas Necessárias

Configure o firewall para permitir:

| Porta | Protocolo | Propósito |
|-------|-----------|-----------|
| 2377 | TCP | Comunicação do cluster (apenas managers) |
| 7946 | TCP/UDP | Descoberta de nodes |
| 4789 | UDP | Overlay network traffic |
| 80 | TCP | HTTP |
| 443 | TCP | HTTPS |
| 8080 | TCP | Dashboard Traefik (opcional) |

### Configuração de Firewall (UFW)

```bash
# Permitir Docker Swarm
sudo ufw allow 2377/tcp
sudo ufw allow 7946/tcp
sudo ufw allow 7946/udp
sudo ufw allow 4789/udp

# Permitir HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Dashboard Traefik (opcional)
sudo ufw allow 8080/tcp
```

## 🚀 Instalação

### Passo 1: Clonar Repositório

```bash
git clone <repository-url>
cd docker_portainer_traefik
```

### Passo 2: Configurar Variáveis de Ambiente

```bash
cp .env.example .env
nano .env
```

**Variáveis obrigatórias:**

```bash
# Seu domínio
DOMAIN=seudominio.com

# Email para Let's Encrypt
ACME_EMAIL=admin@seudominio.com

# Credenciais Cloudflare (para DNS Challenge)
CF_API_EMAIL=seu-email@cloudflare.com
CF_API_KEY=sua-api-key

# Autenticação Traefik Dashboard
TRAEFIK_USER=admin:$$apr1$$hash$$aqui
```

**Gerar hash de senha:**

```bash
echo $(htpasswd -nb admin sua_senha) | sed -e s/\\$/\\$\\$/g
```

### Passo 3: Inicializar Docker Swarm

Execute o script interativo:

```bash
chmod +x swarm-init.sh
./swarm-init.sh
```

**Opções:**

1. **Manager (Primeiro node)**: Inicializa um novo cluster
2. **Worker**: Adiciona como worker a um cluster existente
3. **Manager adicional**: Adiciona como manager a um cluster existente

**Exemplo de saída:**

```
╔═══════════════════════════════════════════════════════════╗
║   Docker Swarm - Traefik 2.11.3 + Portainer              ║
║   Script de Inicialização                                ║
╚═══════════════════════════════════════════════════════════╝

════════════════════════════════════════
  Inicializando Swarm como Manager
════════════════════════════════════════

✓ Swarm inicializado com sucesso!

Token para adicionar WORKERS:
docker swarm join --token SWMTKN-1-xxx... 192.168.1.100:2377

Token para adicionar MANAGERS:
docker swarm join --token SWMTKN-1-yyy... 192.168.1.100:2377
```

### Passo 4: Deploy da Stack

Execute o script de deploy:

```bash
chmod +x swarm-deploy.sh
./swarm-deploy.sh
```

**Opções do script:**

1. **Deploy/Atualizar stack**: Faz o deploy inicial ou atualiza
2. **Remover stack**: Remove completamente a stack
3. **Ver status**: Mostra status dos serviços
4. **Ver logs**: Exibe logs de um serviço específico

## 🏗️ Arquitetura do Cluster

### Cluster Mínimo (Produção)

```
┌─────────────────────────────────────────────────────────┐
│                    MANAGERS (3 nodes)                    │
├─────────────────┬─────────────────┬─────────────────────┤
│   Manager 1     │   Manager 2     │   Manager 3         │
│   (Leader)      │   (Reachable)   │   (Reachable)       │
│                 │                 │                     │
│  Traefik (1/3)  │  Traefik (2/3)  │  Traefik (3/3)      │
│  Portainer      │                 │                     │
│  Agent          │  Agent          │  Agent              │
└─────────────────┴─────────────────┴─────────────────────┘
                           │
            ┌──────────────┴──────────────┐
            │                             │
┌───────────────────┐         ┌───────────────────┐
│    Worker 1       │         │    Worker 2       │
│                   │         │                   │
│  Seus Apps        │         │  Seus Apps        │
│  Agent            │         │  Agent            │
└───────────────────┘         └───────────────────┘
```

### Cluster Simples (Testes)

```
┌─────────────────────────────┐
│      Manager + Worker       │
│       (node único)          │
│                             │
│  Traefik                    │
│  Portainer                  │
│  Agent                      │
│  Seus Apps                  │
└─────────────────────────────┘
```

## 📊 Gerenciamento do Swarm

### Comandos Básicos

```bash
# Ver nodes do cluster
docker node ls

# Ver serviços da stack
docker stack services traefik

# Ver tasks (containers) rodando
docker stack ps traefik

# Ver logs de um serviço
docker service logs -f traefik_traefik
docker service logs -f traefik_portainer

# Inspecionar serviço
docker service inspect traefik_traefik
```

### Escalando Serviços

```bash
# Escalar Portainer para 2 réplicas
docker service scale traefik_portainer=2

# Escalar seu app para 5 réplicas
docker service scale traefik_meu-app=5
```

### Atualizando Serviços (Rolling Update)

```bash
# Atualizar imagem do Traefik
docker service update --image traefik:2.11.4 traefik_traefik

# Atualizar com configuração
docker service update \
  --env-add NEW_VAR=value \
  --replicas 3 \
  traefik_portainer

# Rollback de uma atualização
docker service rollback traefik_traefik
```

### Gerenciamento de Nodes

```bash
# Adicionar label a um node
docker node update --label-add type=worker node-1

# Drenar um node (mover containers)
docker node update --availability drain node-1

# Reativar um node
docker node update --availability active node-1

# Promover worker a manager
docker node promote node-1

# Rebaixar manager a worker
docker node demote node-2
```

## 🔐 Configuração DNS

Configure os registros DNS para apontar para **TODOS** os nodes managers:

```
Tipo    Nome            Conteúdo                Proxy   TTL
─────────────────────────────────────────────────────────────
A       pr              192.168.1.100           OFF     Auto
A       pr              192.168.1.101           OFF     Auto
A       pr              192.168.1.102           OFF     Auto
A       painel          192.168.1.100           OFF     Auto
A       painel          192.168.1.101           OFF     Auto
A       painel          192.168.1.102           OFF     Auto
```

Ou use um balanceador de carga:

```
A       pr              IP_DO_LOAD_BALANCER     OFF     Auto
A       painel          IP_DO_LOAD_BALANCER     OFF     Auto
```

## 🎯 Adicionando Novos Serviços ao Swarm

Crie um arquivo `docker-compose-app.yml`:

```yaml
version: '3.8'

services:
  meu-app:
    image: minha-imagem:latest
    networks:
      - proxy
    deploy:
      mode: replicated
      replicas: 3
      update_config:
        parallelism: 1
        delay: 10s
      restart_policy:
        condition: on-failure
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.app.rule=Host(`app.${DOMAIN}`)"
        - "traefik.http.routers.app.entrypoints=https"
        - "traefik.http.routers.app.tls=true"
        - "traefik.http.routers.app.tls.certresolver=cloudflare"
        - "traefik.http.services.app.loadbalancer.server.port=8000"

networks:
  proxy:
    external: true
```

Deploy:

```bash
docker stack deploy -c docker-compose-app.yml meu-app
```

## 🔄 Diferenças: Compose vs Swarm

| Característica | Docker Compose | Docker Swarm (Stack) |
|----------------|----------------|----------------------|
| Labels | Na raiz do serviço | Em `deploy.labels` |
| Réplicas | Não suportado | `deploy.replicas` |
| Restart | `restart:` | `deploy.restart_policy` |
| Constraints | ❌ | `deploy.placement.constraints` |
| Updates | Manual | `deploy.update_config` |
| Rede | bridge | overlay |

## 🛠️ Troubleshooting

### Serviço não inicia

```bash
# Ver por que o serviço falhou
docker service ps traefik_traefik --no-trunc

# Ver logs detalhados
docker service logs --tail 100 traefik_traefik
```

### Certificados SSL não são gerados

```bash
# Verificar logs do Traefik
docker service logs traefik_traefik | grep -i acme

# Verificar se Cloudflare está configurado
docker service inspect traefik_traefik | grep CF_
```

### Node não se conecta ao cluster

```bash
# No node que não conecta
docker swarm leave --force

# No manager, obter novo token
docker swarm join-token worker

# Tentar juntar novamente
docker swarm join --token <TOKEN> <MANAGER-IP>:2377
```

### Rede overlay com problemas

```bash
# Remover e recriar rede
docker network rm proxy
docker network create --driver overlay --attachable proxy

# Redeployar stack
./swarm-deploy.sh
```

## 📈 Monitoramento

### Comandos de Monitoramento

```bash
# Ver uso de recursos por serviço
docker stats

# Ver eventos do Swarm
docker events --filter type=service

# Health check dos serviços
docker service ls

# Inspecionar saúde de um serviço
docker service ps traefik_traefik
```

### Integração com Prometheus/Grafana

O Traefik já expõe métricas. Adicione ao `docker-stack.yml`:

```yaml
  prometheus:
    image: prom/prometheus:latest
    # ... configuração

  grafana:
    image: grafana/grafana:latest
    # ... configuração
```

## 🔒 Secrets no Swarm

Para credenciais sensíveis, use Docker Secrets:

```bash
# Criar secret
echo "minha-senha-secreta" | docker secret create db_password -

# Listar secrets
docker secret ls

# Usar no stack
services:
  app:
    secrets:
      - db_password

secrets:
  db_password:
    external: true
```

## 🚨 Backup e Recuperação

### Backup dos dados

```bash
# Backup do Portainer
docker run --rm \
  -v traefik_portainer-data:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/portainer-backup.tar.gz /data

# Backup dos certificados
docker run --rm \
  -v traefik_traefik-certificates:/certs \
  -v $(pwd):/backup \
  alpine tar czf /backup/traefik-certs-backup.tar.gz /certs
```

### Restauração

```bash
# Restaurar Portainer
docker run --rm \
  -v traefik_portainer-data:/data \
  -v $(pwd):/backup \
  alpine sh -c "cd / && tar xzf /backup/portainer-backup.tar.gz"
```

## 📚 Recursos Adicionais

- [Docker Swarm Documentation](https://docs.docker.com/engine/swarm/)
- [Traefik Swarm Documentation](https://doc.traefik.io/traefik/providers/docker/#docker-swarm-mode)
- [Portainer Swarm Guide](https://docs.portainer.io/admin/environments/add/swarm)

## 🎓 Próximos Passos

1. Configure monitoramento com Prometheus/Grafana
2. Implemente backup automatizado
3. Configure alertas (AlertManager)
4. Adicione mais workers conforme carga
5. Implemente CI/CD para deploys automáticos

## 💡 Dicas de Produção

✅ **Sempre use 3+ managers** para quorum
✅ **Mantenha managers em datacenters diferentes** para redundância
✅ **Use constraints** para controlar onde os serviços rodam
✅ **Configure health checks** em todos os serviços
✅ **Monitore o cluster** constantemente
✅ **Faça backups regulares** dos volumes
✅ **Teste rollbacks** antes de precisar deles
✅ **Use secrets** para dados sensíveis

---

**Dúvidas?** Consulte o README.md principal ou abra uma issue!
