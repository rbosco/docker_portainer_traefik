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
- **n8n** (opcional): `https://n8n.seudominio.com`
- **Remotion Studio** (opcional): `https://remotion.seudominio.com`
- **MinIO Console** (opcional): `https://minio.seudominio.com`
- **MinIO API S3** (opcional): `https://s3.seudominio.com`

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

# Email para Let's Encrypt (porta 80 deve estar acessível)
ACME_EMAIL=admin@seudominio.com

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

**Stacks suportadas:**

1. Traefik + Portainer (infraestrutura)
2. WordPress
3. n8n (automação de workflows)
4. Remotion + MinIO (geração de vídeos + storage S3)

### Rodar n8n no Swarm e corrigir 404

O 404 ocorre quando o Traefik não encontra roteador para o host da requisição. A rota do n8n vem das **labels** do serviço; o host deve ser o mesmo do `.env`. Siga esta ordem:

**1. Pré-requisitos**

- Swarm ativo: `docker info | grep -i swarm` deve mostrar "Swarm: active".
- Executar no diretório do repositório: `./swarm-deploy.sh`.
- `.env` com:
  - `DOMAIN=seudominio.com` (sem www, sem barra no fim)
  - `SUBDOMAIN_N8N=n8n`
  - `N8N_ENCRYPTION_KEY` definida (o script gera na primeira vez se não existir `data/n8n/config`).

**2. Redes**

- Traefik e n8n precisam estar na **mesma rede** ("proxy"). O script cria a rede **proxy** ao rodar.
- Se aparecer **504 Gateway Timeout**: muitas vezes Traefik está em uma rede e o n8n em outra (ex.: `traefik_proxy` vs `proxy`). Faça **redeploy da stack Traefik** primeiro: `./swarm-deploy.sh` → opção **1** → opção **1**. Assim o Traefik passa a usar a rede "proxy" e consegue alcançar o n8n.

**3. Ordem de deploy**

1. Stack **traefik** primeiro: `./swarm-deploy.sh` → opção **1** → opção **1**.
2. Stack **n8n** sempre pelo script: `./swarm-deploy.sh` → opção **3** (n8n) → opção **1** (Deploy/Atualizar).

Não use `docker stack deploy -c docker-stack-n8n.yml n8n` manualmente; o script substitui o host no YAML para as labels ficarem corretas.

**4. Verificações**

- `docker service ls` → `n8n_n8n` em **1/1**.
- Acesse **exatamente** `https://n8n.seudominio.com` (o host do `.env`).
- DNS: registro A para o subdomínio (ex.: n8n) apontando para o IP do servidor.

**5. Se o 404 continuar**

- Conferir regra: `docker service inspect n8n_n8n --format '{{json .Spec.Labels}}'` → as labels `traefik.http.routers.n8n-secure.rule` e `traefik.http.routers.n8n.rule` devem ter `Host(\`n8n.seudominio.com\`)`. Se estiver vazio ou `Host(\`n8n.\`)`, refaça o deploy pelo script com o `.env` correto.
- Dashboard Traefik: `https://pr.seudominio.com` → verificar se existe roteador para o host do n8n.
- Checklist completo: ver [TROUBLESHOOTING.md](TROUBLESHOOTING.md), seção "n8n: 404 page not found".

**6. 504 Gateway Timeout**

- Significa que o Traefik encontrou a rota mas não consegue falar com o container n8n (rede diferente).
- Confirme que existe só uma rede em uso para ambos: `docker network ls` → deve haver **proxy**. Se existir **traefik_proxy** e **proxy**, o Traefik pode estar em traefik_proxy e o n8n em proxy.
- **Solução:** redeploy da stack **Traefik** (opção 1 → 1). O `docker-stack.yml` atual usa a rede externa "proxy"; após o redeploy, Traefik e n8n ficam na mesma rede e o 504 some.

### Stack 4: Remotion + MinIO (Studio + Render + Storage S3)

Gera vídeos programaticamente via [Remotion](https://www.remotion.dev/) (framework React) com dois serviços principais e storage S3 self-hosted (MinIO).

**Arquitetura:**

- `remotion-studio` — UI web em `https://remotion.${DOMAIN}` (editor visual das compositions), protegido por BasicAuth (`REMOTION_BASIC_AUTH` no `.env`, separado do `TRAEFIK_USER` do dashboard).
- `remotion-render` — API Express (`POST /renders`, `GET /renders/:id`, `GET /health`) em `./remotion/server/`, com render via `@remotion/renderer` e upload do MP4 para o MinIO (variáveis `S3_*` injetadas pela stack). **Sem rota Traefik**; acessível apenas na rede overlay `remotion_internal`.
- `minio` — Storage S3-compatível. Console em `https://minio.${DOMAIN}`, API em `https://s3.${DOMAIN}`.
- `minio-setup` — Init container (`minio/mc`) que cria o bucket `remotion` na primeira subida.

O projeto Remotion deste repositório fica em **`./remotion/`** (versionado). Só se essa pasta **não** existir (ex.: clone antigo sem a pasta), o `swarm-deploy.sh` oferece clonar o template oficial [`remotion-dev/template-render-server`](https://github.com/remotion-dev/template-render-server) como fallback.

**Pré-requisitos:**

- Stack **Traefik** já rodando (opção 1).
- **6 GB RAM livres no manager** (render = 4 GB, studio = 2 GB, MinIO ≈ 256 MB).
- `git` instalado no manager **apenas** se for usar o fallback de clone do template (repositório padrão já traz `./remotion/`).
- DNS configurado para 3 subdomínios:
  - `remotion.${DOMAIN}` → IP do servidor
  - `minio.${DOMAIN}` → IP do servidor
  - `s3.${DOMAIN}` → IP do servidor

**Deploy:**

```bash
# Opcional em SSH com DOCKER_CONTEXT remoto herdado:
# export SWARM_DEPLOY_FORCE_LOCAL=1
./swarm-deploy.sh
# 1) Escolher stack -> 4 (Remotion + MinIO)
# 2) Escolher -> 1 (Deploy/Atualizar)
```

Na primeira execução o script:
1. Usa `./remotion/` do repositório (ou pergunta se deseja clonar o template se a pasta não existir).
2. Builda a imagem local `remotion-local:latest` (5-10 min).
3. Gera `MINIO_ROOT_PASSWORD` no `.env` se estiver vazia.
4. Confirma o endpoint Docker e executa `docker stack deploy -c docker-stack-remotion.yml remotion` (ver também [TROUBLESHOOTING.md](TROUBLESHOOTING.md) se a stack não aparecer no Portainer).

**Studio não abre no navegador** (mensagem tipo "Não é possível acessar esse site"):

Na prática costuma ser **DNS**, **firewall** (80/443), **stack sem réplicas saudáveis** (0/1), **Let's Encrypt** ou **Docker CLI apontando para outro daemon** — não falta de flag do Remotion: o `docker-stack-remotion.yml` já usa `--ipv4` e `--host 0.0.0.0` no Studio, como recomenda a [documentação oficial de deploy do Studio](https://www.remotion.dev/docs/studio/deploy-server). Siga a checklist em [TROUBLESHOOTING.md](TROUBLESHOOTING.md) (secção *Stack `remotion` (ou outra) invisível no Portainer e sem routers no Traefik*), que cobre `dig`, `docker stack services remotion`, `SWARM_DEPLOY_FORCE_LOCAL=1`, etc.

**Customizar as compositions:**

```bash
# Edite os componentes React em:
./remotion/src/
# Rebuild da imagem:
docker build -t remotion-local:latest ./remotion
# Force update do Studio e do Render:
docker service update --force remotion_remotion-studio
docker service update --force remotion_remotion-render
```

**Usar a API via n8n:**

A rede `remotion_internal` é `attachable`. Para o n8n chamar a API de render, conecte o container ao overlay uma única vez após o deploy:

```bash
docker network connect remotion_internal $(docker ps -qf name=n8n_n8n | head -1)
```

Depois, no workflow do n8n use **HTTP Request**:

```
POST http://remotion-render:3000/renders
Content-Type: application/json
{
  "compositionId": "HelloWorld",
  "inputProps": { "title": "Olá do n8n" }
}

-> resposta: { "id": "<render-id>", "status": "queued" }
```

Polling do status:

```
GET http://remotion-render:3000/renders/<render-id>
-> quando status = "done": use o campo "url" (MP4 público em https://s3.${DOMAIN}/<bucket>/renders/<id>.mp4)
```

A API de render já faz upload para o MinIO usando `S3_ENDPOINT`, `S3_PUBLIC_ENDPOINT`, `S3_ACCESS_KEY`, `S3_SECRET_KEY`, `S3_BUCKET` (definidas em [docker-stack-remotion.yml](docker-stack-remotion.yml)). Composition de exemplo incluída: **`HelloWorld`** (veja `./remotion/src/compositions/`).

**MinIO Console:**

- URL: `https://minio.${DOMAIN}`
- Usuário: valor de `MINIO_ROOT_USER` no `.env` (default `admin`)
- Senha: valor de `MINIO_ROOT_PASSWORD` (gerada pelo script na 1ª subida)

**Pitfalls conhecidos (doc oficial + comunidade):**

- **Não use Alpine** como base — Remotion tem 2 bugs documentados com Alpine. O Dockerfile do template já usa Debian bookworm.
- **Flag `--ipv4`** obrigatória (v4.0.125+) atrás de proxy — já configurada no `command` do studio.
- **`--max-old-space-size=4096`** no `NODE_OPTIONS` evita OOM no heap durante render pesado.
- **Cachear `bundle()`** uma única vez no startup do servidor (já é padrão do template oficial). Não faça `bundle()` por request.
- **Constraint `node.role == manager`**: a imagem `remotion-local:latest` só existe no manager (sem registry). Se você adicionar workers ao Swarm, migre para GHCR/Docker Hub antes.
- **Fontes**: emojis e CJK não vêm por padrão. Adicione `RUN apt-get install -y fonts-noto-color-emoji fonts-noto-cjk` no `./remotion/Dockerfile` e rebuild.

**Ver logs:**

```bash
./swarm-deploy.sh  # -> 4 -> 4 (Ver logs)
# submenu: 1) Studio  2) Render  3) MinIO  4) MinIO Setup
```

**Limpeza completa:**

```bash
./swarm-deploy.sh  # -> 4 -> 5 (Limpeza completa)
# Digite 'LIMPAR' para confirmar remoção de stack + volume minio_data.
# Opcionalmente remove ./remotion e a imagem remotion-local:latest.
```

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
        - "traefik.http.routers.app.tls.certresolver=letsencrypt"
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
```

Confirme `ACME_EMAIL` no `.env` e que a porta 80 está acessível da internet.

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
