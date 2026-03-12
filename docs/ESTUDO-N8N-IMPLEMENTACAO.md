# Estudo da implementação: n8n + Portainer + Traefik

Documento de análise do que foi implementado para integrar o n8n ao ambiente Docker Swarm com Traefik e Portainer.

---

## 1. Visão geral

| Componente | Função |
|------------|--------|
| **Traefik** | Reverse proxy, TLS (Let's Encrypt/Cloudflare), roteamento por host. Timeouts ajustados para n8n (workflows longos, SSE/WebSocket). |
| **Portainer** | UI para gerenciar stacks e containers; deploy do n8n pode ser feito por ele ou pelo script. |
| **n8n** | Automação de workflows; exposto via subdomínio (ex.: `https://n8n.seudominio.com`) na mesma rede do Traefik. |

O subdomínio é configurado no `.env` (`SUBDOMAIN_N8N` + `DOMAIN`); a URL final é `https://<SUBDOMAIN_N8N>.<DOMAIN>`.

---

## 2. Arquivos criados ou alterados

### 2.1 Stack Swarm (produção)

**`docker-stack-n8n.yml`**

- **Serviço:** `n8n`, imagem fixa `docker.n8n.io/n8nio/n8n:2.11.3`.
- **Rede:** `proxy` com `name: traefik_proxy` (rede externa da stack Traefik). **Crítico:** n8n e Traefik precisam estar na mesma rede; antes o n8n usava a rede `proxy` (outra overlay), o que gerava 504. Com `name: traefik_proxy`, ambos ficam na mesma rede.
- **Variáveis de ambiente:** `TZ`, `GENERIC_TIMEZONE`, `N8N_ENCRYPTION_KEY`, `N8N_PROTOCOL`, `N8N_HOST`, `WEBHOOK_URL`, `N8N_PROXY_HOPS=1`, `NODE_ENV`, `N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS`, `N8N_PYTHON_ENABLED=false`.
- **Volumes:** `n8n_data` → `/home/node/.n8n` (workflows e configurações).
- **Deploy:** 1 réplica, `endpoint_mode: dnsrr` (evita VIP obsoleto no Swarm), placement em manager, `stop_grace_period: 120s` (nível do serviço), reserva/limite de memória (512M / 1G), `update_config` com `order: start-first` e `delay: 30s`, `restart_policy` com delay 10s e max_attempts 5.
- **Labels Traefik:** HTTP → redirect HTTPS, HTTPS com TLS e `certresolver=cloudflare`, porta 5678. Host vem de `SUBDOMAIN_N8N` e `DOMAIN` do `.env`.
- **Sem healthcheck:** healthcheck foi removido para evitar SIGTERM por falha de checagem durante migrações/start.

### 2.2 Compose local (testes)

**`docker-compose-n8n.yml`**

- Uso: com Traefik (`docker compose up -d` depois `docker compose -f docker-compose-n8n.yml up -d`) ou só n8n (`docker network create proxy` depois compose).
- Porta 5678 exposta; rede `proxy` externa (no Compose local a stack principal cria `proxy` como bridge).
- Imagem `latest`; variáveis com fallback para teste sem `.env` (ex.: `N8N_ENCRYPTION_KEY=change_me_local_test`, `WEBHOOK_URL` em http com porta).
- Labels Traefik iguais ao padrão do projeto; `traefik.docker.network=proxy` para o Traefik descobrir o container.

### 2.3 Traefik (ajustes para n8n)

**`docker-stack.yml`**

- **Entrypoints:** timeouts em HTTP e HTTPS: `readTimeout=0`, `writeTimeout=0`, `idleTimeout=600` (evita corte em workflows longos e SSE/WebSocket).
- **serversTransport (Traefik → backend):** `dialTimeout=300`, `responseHeaderTimeout=0`, `idleConnTimeout=90`.

**`traefik/traefik.yml` e `traefik/traefik-swarm.yml`**

- Comentários e timeouts já alinhados ao n8n (uso em Compose; no Swarm o Traefik é configurado via command no docker-stack.yml).

### 2.4 Script de deploy

**`swarm-deploy.sh`**

- Opção **3) n8n** no menu; valida Traefik rodando e variáveis `SUBDOMAIN_N8N`, `N8N_ENCRYPTION_KEY`; cria `data/n8n` se necessário.
- Após deploy: exibe URL do n8n e lembrete de DNS.
- Logs: stack n8n usa serviço `n8n` (comando interno `n8n_n8n`).
- Limpeza: remove stack, volume `n8n_n8n_data` e opcionalmente `data/n8n`.

**Ponto de melhoria:** ao final o script sempre mostra “Comandos úteis” com `docker service logs -f ${STACK_NAME}_traefik` e `_portainer`. Quando a stack escolhida é n8n, o correto seria `n8n_n8n` (e não escalar portainer). Sugestão: usar comandos condicionais por `STACK_NAME`.

### 2.5 Configuração e documentação

**`.env.example`**

- `SUBDOMAIN_N8N`, `N8N_PROTOCOL`, `N8N_ENCRYPTION_KEY`; comentários sobre `WEBHOOK_URL` e `N8N_PROXY_HOPS` (a stack já define com base em SUBDOMAIN_N8N e DOMAIN).

**`README.md`**

- Estrutura do projeto com `docker-compose-n8n.yml`; seção “Testar n8n localmente” com comandos; URL do n8n em produção; exemplo de DNS com IP 178.156.200.149 (pr, painel, n8n).

**`README-SWARM.md`**

- Seção “Rodar n8n no Swarm e corrigir 404” com pré-requisitos, ordem de deploy e verificações.
- **Desatualizado:** fala em “proxy e n8n_network” e em Traefik entrar na “rede do n8n”. Na prática, o n8n usa a rede **traefik_proxy** (external name no docker-stack-n8n.yml). Vale atualizar a seção de redes para: “O n8n usa a rede externa **traefik_proxy** (criada pela stack Traefik). Não é necessário rede adicional.”

**`setup.sh`**

- Já existia: pergunta se instala n8n, pede subdomínio, grava `SUBDOMAIN_N8N`, `N8N_PROTOCOL`, `N8N_ENCRYPTION_KEY` no `.env`, cria `data/n8n`.

---

## 3. Fluxo de tráfego (produção Swarm)

```
Cliente → HTTPS (443) → Traefik (roteador n8n-secure, Host=SUBDOMAIN_N8N.DOMAIN)
                              → backend: serviço n8n (tasks.n8n_n8n:5678)
                              → rede: traefik_proxy (mesma que Traefik)
```

- Variáveis `N8N_HOST` e `WEBHOOK_URL` no container n8n usam o mesmo host, para webhooks e OAuth gerarem URLs públicas corretas.

---

## 4. Problemas encontrados e soluções aplicadas

| Problema | Causa / observação | Solução |
|----------|--------------------|--------|
| 504 Gateway Timeout | Traefik não alcançava o n8n (redes diferentes) ou timeouts curtos. | n8n na rede **traefik_proxy** (`name: traefik_proxy`). Timeouts aumentados no Traefik (entrypoints + serversTransport). |
| 504 por VIP obsoleto no Swarm | Backend resolvido para VIP antigo após restart. | `endpoint_mode: dnsrr` no serviço n8n. |
| SIGTERM / reinícios | Healthcheck falhando durante migrações; possível substituição por nova imagem. | Healthcheck removido; imagem fixa 2.11.3; reserva/limite de memória; stop_grace_period 120s; update_config order start-first. |
| “stop_grace_period is not allowed” | Propriedade dentro de `deploy`. | `stop_grace_period` movido para o nível do serviço (ao lado de image, volumes, networks). |
| Aviso “Python 3 is missing” | Runner Python em modo interno. | `N8N_PYTHON_ENABLED=false`; comentário no stack explicando que o aviso é inofensivo. |

---

## 5. Checklist de produção

- [ ] `.env` com `DOMAIN`, `SUBDOMAIN_N8N`, `N8N_ENCRYPTION_KEY`, `N8N_PROTOCOL` (e Cloudflare se usar Let's Encrypt).
- [ ] Stack Traefik deployada antes do n8n.
- [ ] Deploy do n8n via `./swarm-deploy.sh` → 3) n8n → 1) Deploy/Atualizar.
- [ ] DNS: registro A de `<SUBDOMAIN_N8N>.<DOMAIN>` para o IP do servidor (ex.: 178.156.200.149).
- [ ] Acesso: `https://<SUBDOMAIN_N8N>.<DOMAIN>`; configurar usuário admin no primeiro uso.
- [ ] Logs do n8n: `docker service logs -f n8n_n8n`. Eventos de reinício: `docker events --filter service=n8n_n8n`.

---

## 6. Melhorias sugeridas (opcionais)

1. **swarm-deploy.sh:** “Comandos úteis” no final condicionais à stack (para n8n: `docker service logs -f n8n_n8n`, sem exemplo de scale portainer).
2. **README-SWARM.md:** Atualizar a seção “Rodar n8n no Swarm” (redes) para explicar que o n8n usa a rede externa `traefik_proxy` e que não existe “n8n_network” no fluxo atual.
3. **docker-compose-n8n.yml:** Alinhar imagem para versão fixa (ex.: 2.11.3) se quiser o mesmo comportamento do Swarm em testes locais.
4. **PostgreSQL:** Para produção com mais carga ou HA, considerar adicionar serviço Postgres e variáveis `DB_*` no docker-stack-n8n.yml (hoje usa SQLite no volume).

---

## 7. Resumo

A implementação cobre:

- Stack Swarm do n8n na rede correta (traefik_proxy), com Traefik configurado para timeouts longos e backend na porta 5678.
- Deploy e limpeza integrados ao `swarm-deploy.sh`, variáveis no `.env` e documentação no README e README-SWARM.
- Compose local para testes com ou sem Traefik.
- Mitigações para 504 (rede, timeouts, dnsrr), SIGTERM (sem healthcheck, imagem fixa, recursos e stop_grace_period) e aviso do Python (N8N_PYTHON_ENABLED=false).

Pendências opcionais: comandos úteis condicionais no script, doc de redes no README-SWARM e, se desejado, versão fixa no compose local e opção de PostgreSQL na stack n8n.
