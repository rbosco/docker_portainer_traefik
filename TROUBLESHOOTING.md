# 🔧 Troubleshooting - Guia de Resolução de Problemas

## Erro: ERR_SSL_UNRECOGNIZED_NAME_ALERT

Este erro significa que o navegador não reconhece o certificado SSL apresentado pelo servidor.

### 🔍 Diagnóstico Rápido

Execute o script de diagnóstico:

```bash
./diagnostico-ssl.sh
```

Este script verifica automaticamente:
- ✓ Status dos containers
- ✓ Configuração do arquivo .env
- ✓ Resolução DNS dos domínios
- ✓ Certificados gerados (acme.json)
- ✓ Logs do Traefik
- ✓ Conectividade com API da Cloudflare

---

## 📋 Causas Comuns e Soluções

### 1. DNS Não Configurado no Cloudflare

**Sintoma:** Erro `ERR_SSL_UNRECOGNIZED_NAME_ALERT` ao acessar o site

**Causa:** O domínio não está apontando para o IP do servidor

**Solução:**

1. Acesse o [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Selecione seu domínio
3. Vá em **DNS** → **Records**
4. Adicione os registros:

```
Tipo: A
Nome: pr (ou seu SUBDOMAIN_TRAEFIK)
Conteúdo: IP_DO_SEU_SERVIDOR
Proxy: Desabilitado (ícone cinza - somente DNS)
TTL: Auto
```

```
Tipo: A
Nome: painel (ou seu SUBDOMAIN_PORTAINER)
Conteúdo: IP_DO_SEU_SERVIDOR
Proxy: Desabilitado (ícone cinza - somente DNS)
TTL: Auto
```

**IMPORTANTE:** O proxy da Cloudflare (nuvem laranja) deve estar **DESABILITADO** para Let's Encrypt funcionar!

**Verificar:**
```bash
dig +short pr.seudominio.com
# Deve retornar o IP do seu servidor
```

---

### 2. Credenciais da Cloudflare Incorretas

**Sintoma:** Certificados não são gerados, acme.json permanece vazio

**Causa:** CF_API_KEY ou CF_DNS_API_TOKEN inválidos ou mal configurados

**Solução:**

#### Opção A: API Key Global (Recomendado)

1. Acesse [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Role até **API Keys** → **Global API Key** → **View**
3. Copie a chave

No arquivo `.env`:
```bash
CF_API_EMAIL=seu-email@cloudflare.com
CF_API_KEY=sua_api_key_global_aqui
```

#### Opção B: API Token DNS (Mais Seguro)

1. Acesse [Cloudflare API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Clique em **Create Token**
3. Use o template **Edit zone DNS**
4. Configure:
   - **Permissions:** Zone - DNS - Edit
   - **Zone Resources:** Include - Specific zone - seu domínio
5. Clique em **Continue to summary** → **Create Token**
6. Copie o token (será mostrado apenas uma vez!)

No arquivo `.env`:
```bash
CF_DNS_API_TOKEN=seu_token_dns_aqui
# Remova ou comente CF_API_EMAIL e CF_API_KEY
```

**Testar credenciais:**
```bash
# Com API Key:
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "X-Auth-Email: seu-email@cloudflare.com" \
  -H "X-Auth-Key: sua_api_key" \
  -H "Content-Type: application/json"

# Com API Token:
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
  -H "Authorization: Bearer seu_token" \
  -H "Content-Type: application/json"

# Resposta esperada: {"result":{"status":"active"},"success":true}
```

---

### Traefik: resetar senha do dashboard

**Sintoma:** Não consigo logar no dashboard do Traefik (ex.: `https://pr.seudominio.com`); a senha foi esquecida ou precisa ser alterada.

**Causa:** O dashboard usa HTTP Basic Auth. O usuário e a senha vêm da variável `TRAEFIK_USER` no `.env`, no formato `usuario:hash_htpasswd`. Para alterar a senha é preciso gerar um novo hash, atualizar o `.env` e redeployar a stack Traefik.

**Passos:**

1. **Gerar o hash da nova senha**  
   No servidor (ou máquina com `htpasswd`; no Ubuntu: `sudo apt install apache2-utils`), execute (substitua `usuario` e `senha` pelo usuário e senha desejados; use aspas na senha se tiver caracteres especiais como `@`):
   ```bash
   echo $(htpasswd -nb usuario 'senha') | sed -e s/\\$/\\$\\$/g
   ```
   Copie a saída inteira (ex.: `usuario:$$apr1$$...$$...`).

2. **Atualizar o .env**  
   No diretório do projeto, edite o arquivo `.env` e altere a linha:
   ```env
   TRAEFIK_USER=valor_copiado_no_passo_1
   ```
   Salve o arquivo.

3. **Redeploy da stack Traefik**  
   Para o Traefik passar a usar o novo `TRAEFIK_USER`:
   ```bash
   ./swarm-deploy.sh
   ```
   Escolha a opção **1** (Traefik) e depois **1** (Deploy/Atualizar). Em seguida acesse o dashboard com o novo usuário e senha.

---

### 3. Arquivo acme.json com Permissões Incorretas

**Sintoma:** Traefik não consegue salvar certificados, erro nos logs

**Causa:** Permissões do arquivo acme.json diferentes de 600

**Solução:**

```bash
chmod 600 data/traefik/acme.json
```

**Verificar:**
```bash
ls -la data/traefik/acme.json
# Deve mostrar: -rw------- (600)
```

---

### 4. Certificados Não Foram Gerados

**Sintoma:** acme.json está vazio ou muito pequeno (< 50 bytes)

**Causa:** Traefik ainda não conseguiu obter certificados do Let's Encrypt

**Solução:**

1. **Verificar logs em tempo real:**
   ```bash
   docker logs traefik -f
   ```

2. **Procurar por erros relacionados a:**
   - `acme`
   - `cloudflare`
   - `certificate`
   - `error`

3. **Forçar regeneração dos certificados:**
   ```bash
   # Parar o Traefik
   docker-compose down

   # Limpar certificados antigos
   rm data/traefik/acme.json
   touch data/traefik/acme.json
   chmod 600 data/traefik/acme.json

   # Reiniciar
   docker-compose up -d

   # Acompanhar logs
   docker logs traefik -f
   ```

4. **Aguardar 2-3 minutos** para o Traefik tentar obter os certificados

---

### 5. Rate Limit do Let's Encrypt

**Sintoma:** Erro nos logs: "too many certificates already issued"

**Causa:** Excedeu o limite de 5 certificados por domínio por semana

**Solução:**

**Temporária - Usar Staging (para testes):**

Edite `traefik/traefik.yml` ou `traefik/traefik-swarm.yml`:

```yaml
certificatesResolvers:
  cloudflare:
    acme:
      email: ${ACME_EMAIL}
      storage: /certificates/acme.json
      caServer: https://acme-staging-v02.api.letsencrypt.org/directory  # Staging!
      dnsChallenge:
        provider: cloudflare
```

Reinicie e teste. Quando funcionar, remova a linha `caServer` para usar produção.

**Definitiva - Aguardar:**

Espere 7 dias ou use um subdomínio diferente temporariamente.

---

### 6. Firewall Bloqueando Portas

**Sintoma:** Site não carrega ou timeout

**Causa:** Portas 80 e 443 bloqueadas

**Solução:**

```bash
# Verificar se as portas estão abertas
sudo ufw status

# Abrir portas (se usando UFW)
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw reload

# Verificar se Traefik está escutando
netstat -tlnp | grep -E ':80|:443'
```

---

### 7. Domínio Não Configurado no .env

**Sintoma:** Traefik tenta gerar certificado para "localhost" ou domínio errado

**Causa:** Variável DOMAIN não configurada corretamente no .env

**Solução:**

Edite `.env` e verifique:

```bash
DOMAIN=seudominio.com  # SEM https://, SEM www, SEM barra no final
SUBDOMAIN_TRAEFIK=pr
SUBDOMAIN_PORTAINER=painel
```

Reinicie:
```bash
docker-compose down
docker-compose up -d
```

---

### 8. Proxy da Cloudflare Ativado

**Sintoma:** Certificado válido mas erro de conexão ou loop infinito

**Causa:** Proxy da Cloudflare (nuvem laranja) está ativado

**Solução:**

No Cloudflare Dashboard, em DNS Records:
- Clique na **nuvem laranja** ao lado do registro
- Deve ficar **cinza** (DNS Only)
- Aguarde propagação (alguns minutos)

**Por quê?**
- Com proxy ativado: Cloudflare intercepta a conexão
- Let's Encrypt precisa se conectar diretamente ao servidor
- Use "DNS Only" para DNS Challenge funcionar

---

## 🔬 Comandos Úteis para Diagnóstico

### Ver logs do Traefik


```bash
# Docker Compose
docker logs traefik -f

# Docker Swarm
docker service logs traefik_traefik -f

# Filtrar apenas erros
docker logs traefik 2>&1 | grep -i error
```

### Verificar certificados gerados

```bash
# Ver conteúdo do acme.json (se tiver jq instalado)
cat data/traefik/acme.json | jq '.cloudflare.Certificates[].domain.main'

# Ver tamanho do arquivo
ls -lh data/traefik/acme.json

# Deve ter mais de 50 bytes se certificados foram gerados
```

### Testar resolução DNS

```bash
# Verificar se DNS aponta para o IP correto
dig +short pr.seudominio.com
nslookup pr.seudominio.com

# Testar de servidor DNS público
dig @8.8.8.8 pr.seudominio.com
```

### Verificar conectividade HTTPS

```bash
# Testar conexão SSL
openssl s_client -connect pr.seudominio.com:443 -servername pr.seudominio.com

# Ver certificado retornado
echo | openssl s_client -connect pr.seudominio.com:443 2>/dev/null | openssl x509 -noout -text | grep -A 2 "Subject:"
```

### Verificar se containers estão rodando

```bash
# Listar containers
docker ps

# Ver status detalhado
docker-compose ps  # Compose
docker stack ps traefik  # Swarm
```

---

## 📚 Fluxo de Resolução Recomendado

### Passo 1: Execute o Diagnóstico
```bash
./diagnostico-ssl.sh
```

### Passo 2: Verifique DNS
```bash
dig +short pr.seudominio.com
dig +short painel.seudominio.com
```
**Deve retornar o IP do seu servidor**

### Passo 3: Verifique Credenciais Cloudflare
No arquivo `.env`:
- CF_API_EMAIL e CF_API_KEY **OU**
- CF_DNS_API_TOKEN

### Passo 4: Verifique Logs
```bash
docker logs traefik -f
```
Procure por erros relacionados a:
- DNS challenge
- Cloudflare
- Certificate
- ACME

### Passo 5: Regenere Certificados (se necessário)
```bash
docker-compose down
rm data/traefik/acme.json
touch data/traefik/acme.json
chmod 600 data/traefik/acme.json
docker-compose up -d
docker logs traefik -f  # Acompanhe a geração
```

### Passo 6: Aguarde e Teste
- Aguarde 2-3 minutos
- Verifique se acme.json cresceu: `ls -lh data/traefik/acme.json`
- Teste no navegador: `https://pr.seudominio.com`

---

## 🆘 Ainda com Problemas?

### Informações Úteis para Suporte

Ao pedir ajuda, forneça:

1. **Saída do diagnóstico:**
   ```bash
   ./diagnostico-ssl.sh > diagnostico.txt
   ```

2. **Logs do Traefik:**
   ```bash
   docker logs traefik --tail 100 > traefik-logs.txt
   ```

3. **Configuração (SEM CREDENCIAIS!):**
   ```bash
   # Remova CF_API_KEY, CF_DNS_API_TOKEN antes de compartilhar!
   cat .env
   ```

4. **Teste DNS:**
   ```bash
   dig pr.seudominio.com
   ```

---

## Stack `remotion` (ou outra) invisível no Portainer e sem routers no Traefik

O Portainer CE e o Traefik leem o **mesmo** Docker Swarm que o `docker` CLI quando aponta para o socket do manager (`unix:///var/run/docker.sock`). Não há registro separado: se a stack não existir neste Swarm, não aparece em lugar nenhum; se existir mas o Portainer mostrar outro cluster, o endpoint do Portainer está errado.

### Árvore de diagnóstico (rode na VPS, mesma sessão onde executa `./swarm-deploy.sh`)

**1. Contexto Docker (causa mais comum: deploy foi para outro daemon)**

```bash
docker context show
echo "DOCKER_HOST=${DOCKER_HOST:-<vazio>}"
docker info --format '{{.Name}}'
docker stack ls
```

- Se **`remotion` não aparece** em `docker stack ls`: a stack nunca foi criada neste Swarm (ex.: `DOCKER_CONTEXT` remoto, ou deploy abortado antes do `docker stack deploy`). Traefik e Portainer **não** podem mostrar o que não existe aqui.
- Se **`remotion` aparece** no CLI mas **não** no Portainer: o Portainer está ligado a **outro** ambiente. Em Portainer: **Environments** → confirme que o endpoint em uso é o Swarm deste host (a stack `traefik` usa o agent em `tcp://tasks.agent:9001` — [docker-stack.yml](docker-stack.yml)).

**Forçar o CLI no socket local (sem depender do prompt interativo):**

```bash
export SWARM_DEPLOY_FORCE_LOCAL=1
./swarm-deploy.sh
```

Ou manualmente antes do deploy:

```bash
unset DOCKER_HOST
export DOCKER_CONTEXT=default
docker stack deploy -c docker-stack-remotion.yml remotion
docker stack ls | grep remotion
```

**2. Serviços e réplicas (Traefik só expõe backend se houver task saudável)**

```bash
docker stack services remotion
docker stack ps remotion --no-trunc
```

Se aparecer **0/1** ou tasks `Rejected` / `Failed`: veja a mensagem com `docker service ps remotion_remotion-studio --no-trunc` (imagem `remotion-local:latest` ausente no node, OOM, etc.).

**3. Logs do Traefik**

```bash
docker service logs traefik_traefik --tail 80
```

Procure erros do provider Docker / acesso ao socket.

**4. Routers esperados no Traefik**

Por desenho, **apenas** `remotion-studio` e `minio` têm labels Traefik em [docker-stack-remotion.yml](docker-stack-remotion.yml). O serviço **`remotion-render` não tem host público** (só rede `remotion_internal`); isso é esperado.

**5. Script atualizado**

O [swarm-deploy.sh](swarm-deploy.sh) inclui `ensure_local_docker` (alerta de contexto remoto), reimpressão do endpoint antes de cada `docker stack deploy`, e validação: a stack tem de aparecer em `docker stack ls` logo após o deploy. Se a VPS ainda não tiver essas linhas, faça `git pull` no repositório.

---

## 📖 Recursos Adicionais

- [Documentação do Traefik](https://doc.traefik.io/traefik/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [Cloudflare API Documentation](https://developers.cloudflare.com/api/)
- [Traefik + Cloudflare DNS Challenge](https://doc.traefik.io/traefik/https/acme/#dnschallenge)

---

## ✅ Checklist Final

Antes de buscar ajuda, verifique:

- [ ] DNS configurado e apontando para o IP correto
- [ ] Proxy da Cloudflare DESABILITADO (nuvem cinza)
- [ ] Credenciais da Cloudflare configuradas corretamente no .env
- [ ] Arquivo acme.json com permissões 600
- [ ] Portas 80 e 443 abertas no firewall
- [ ] Containers do Traefik rodando
- [ ] Aguardou pelo menos 3 minutos após iniciar
- [ ] Verificou os logs do Traefik para erros
- [ ] Variável DOMAIN configurada sem https:// ou www
- [ ] Não excedeu rate limit do Let's Encrypt (5 certificados/semana)

Se todos os itens estiverem OK e ainda assim não funcionar, execute `./diagnostico-ssl.sh` e analise a saída detalhadamente.
