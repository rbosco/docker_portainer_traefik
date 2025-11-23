# Docker Stack: Traefik 2.11.3 + Portainer

Estrutura completa para gerenciamento de containers Docker usando Traefik como reverse proxy e Portainer como interface de gerenciamento.

## 📋 Componentes

- **Traefik 2.11.3**: Reverse proxy moderno com suporte a Let's Encrypt
- **Portainer CE**: Interface web para gerenciamento de containers Docker
- **Docker Compose**: Orquestração dos serviços

## 🏗️ Estrutura do Projeto

```
.
├── docker-compose.yml          # Definição dos serviços
├── .env                        # Variáveis de ambiente (não versionado)
├── .env.example               # Exemplo de variáveis de ambiente
├── traefik/
│   ├── traefik.yml           # Configuração estática do Traefik
│   └── dynamic/
│       └── tls.yml           # Configuração TLS dinâmica
└── data/
    ├── traefik/
    │   └── acme.json         # Certificados Let's Encrypt
    └── portainer/            # Dados do Portainer
```

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

### Desenvolvimento Local (sem domínio)

- **Traefik Dashboard**: http://localhost:8080
  - Usuário padrão: `admin`
  - Senha padrão: `admin`

- **Portainer**: http://localhost:9000
  - Configure o usuário admin no primeiro acesso

### Produção (com domínio configurado)

- **Traefik Dashboard**: https://traefik.seudominio.com
- **Portainer**: https://portainer.seudominio.com

## ⚙️ Configuração

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

## 🔧 Comandos Úteis

### Gerenciamento de Containers

```bash
# Iniciar serviços
docker-compose up -d

# Parar serviços
docker-compose down

# Reiniciar serviços
docker-compose restart

# Ver logs
docker-compose logs -f

# Ver logs de um serviço específico
docker-compose logs -f traefik
docker-compose logs -f portainer

# Atualizar imagens
docker-compose pull
docker-compose up -d
```

### Manutenção

```bash
# Limpar containers não utilizados
docker system prune -a

# Backup dos dados do Portainer
tar -czf portainer-backup-$(date +%Y%m%d).tar.gz data/portainer/

# Verificar rede proxy
docker network inspect proxy
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
