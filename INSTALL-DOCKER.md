# 🐳 Guia de Instalação do Docker 24.0.7 para Debian 11

## ⚠️ Por Que Docker 24.0.7?

O **Traefik 2.10.7** requer **Docker 24.0.7** (API 1.43) para funcionar corretamente.

Versões mais recentes do Docker (29.x, 28.x) têm incompatibilidades com o Traefik:
- ❌ Docker 29.x → API 1.52 → **Incompatível**
- ❌ Docker 28.x → API 1.45+ → **Problemas**
- ✅ **Docker 24.0.7** → API 1.43 → **Compatível e Testado**

---

## 📋 Pré-requisitos

- Debian 11 (Bullseye) ou superior
- Acesso root ou sudo
- Conexão com internet

---

## 🔧 Passo a Passo de Instalação

### **1. Remover Versões Antigas do Docker**

```bash
# Parar Docker se estiver rodando
sudo systemctl stop docker 2>/dev/null || true

# Remover versões antigas
sudo apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

# Limpar pacotes órfãos
sudo apt autoremove -y
```

---

### **2. Instalar Dependências**

```bash
# Atualizar lista de pacotes
sudo apt update

# Instalar pacotes necessários
sudo apt install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    apt-transport-https \
    software-properties-common
```

---

### **3. Adicionar Repositório Oficial do Docker**

```bash
# Criar diretório para chaves GPG
sudo install -m 0755 -d /etc/apt/keyrings

# Baixar e adicionar chave GPG do Docker
curl -fsSL https://download.docker.com/linux/debian/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Dar permissões corretas
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Adicionar repositório Docker (Debian 11 Bullseye)
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  bullseye stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Atualizar lista de pacotes
sudo apt update
```

---

### **4. Verificar Versões Disponíveis**

```bash
# Ver versões Docker 24.0.x disponíveis
apt-cache madison docker-ce | grep 24.0
```

**Saída esperada:**
```
docker-ce | 5:24.0.7-1~debian.11~bullseye | https://download.docker.com/linux/debian bullseye/stable amd64 Packages
docker-ce | 5:24.0.6-1~debian.11~bullseye | https://download.docker.com/linux/debian bullseye/stable amd64 Packages
...
```

---

### **5. Instalar Docker 24.0.7**

```bash
# Instalar Docker Engine 24.0.7
sudo apt install -y \
    docker-ce=5:24.0.7-1~debian.11~bullseye \
    docker-ce-cli=5:24.0.7-1~debian.11~bullseye \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin

# Segurar versão (prevenir upgrade automático)
sudo apt-mark hold docker-ce docker-ce-cli
```

**Saída esperada:**
```
docker-ce set on hold.
docker-ce-cli set on hold.
```

---

### **6. Iniciar e Habilitar Docker**

```bash
# Iniciar serviço Docker
sudo systemctl start docker

# Habilitar Docker para iniciar no boot
sudo systemctl enable docker

# Verificar status
sudo systemctl status docker
```

---

### **7. Verificar Instalação**

```bash
# Verificar versão instalada
docker version
```

**Saída esperada:**
```
Client: Docker Engine - Community
 Version:           24.0.7
 API version:       1.43
 Go version:        go1.20.10
 Git commit:        afdd53b
 Built:             Thu Oct 26 09:08:17 2023
 OS/Arch:           linux/amd64
 Context:           default

Server: Docker Engine - Community
 Engine:
  Version:          24.0.7
  API version:      1.43 (minimum version 1.12)
  Go version:       go1.20.10
  Git commit:       311b9ff
  Built:            Thu Oct 26 09:08:17 2023
  OS/Arch:          linux/amd64
  Experimental:     false
```

**Pontos importantes:**
- ✅ Version: **24.0.7**
- ✅ API version: **1.43**
- ✅ Minimum API version: **1.12** (aceita versões antigas)

---

### **8. Adicionar Usuário ao Grupo Docker (Opcional)**

```bash
# Adicionar usuário atual ao grupo docker
sudo usermod -aG docker $USER

# Ativar mudanças (ou faça logout/login)
newgrp docker

# Testar sem sudo
docker ps
```

---

### **9. Inicializar Docker Swarm (Para Este Projeto)**

```bash
# Verificar IP do servidor
ip addr show | grep "inet " | grep -v 127.0.0.1

# Inicializar Swarm com IP detectado
docker swarm init --advertise-addr <SEU_IP>

# Ou deixar Docker detectar automaticamente
docker swarm init
```

**Saída esperada:**
```
Swarm initialized: current node (xxx) is now a manager.
```

---

## ✅ Verificação Final

Execute estes comandos para confirmar que tudo está funcionando:

```bash
# 1. Versão do Docker
docker version --format '{{.Server.Version}}'
# Deve mostrar: 24.0.7

# 2. API version
docker version --format '{{.Server.APIVersion}}'
# Deve mostrar: 1.43

# 3. Status do Swarm
docker info | grep "Swarm:"
# Deve mostrar: Swarm: active

# 4. Testar container simples
docker run --rm hello-world
# Deve baixar e executar com sucesso
```

---

## 🔒 Segurar Versão do Docker

Para **prevenir upgrades automáticos** que podem quebrar compatibilidade:

```bash
# Segurar versão
sudo apt-mark hold docker-ce docker-ce-cli containerd.io

# Verificar pacotes segurados
apt-mark showhold
```

**Para liberar no futuro** (quando houver versão compatível do Traefik):
```bash
sudo apt-mark unhold docker-ce docker-ce-cli containerd.io
```

---

## 🔄 Rollback (Se Necessário)

Se você instalou uma versão mais recente e quer voltar:

```bash
# 1. Parar Docker
sudo systemctl stop docker

# 2. Remover versão atual
sudo apt remove -y docker-ce docker-ce-cli

# 3. Instalar 24.0.7
sudo apt install -y \
    docker-ce=5:24.0.7-1~debian.11~bullseye \
    docker-ce-cli=5:24.0.7-1~debian.11~bullseye

# 4. Segurar versão
sudo apt-mark hold docker-ce docker-ce-cli

# 5. Reiniciar
sudo systemctl start docker
docker version
```

---

## ❓ Troubleshooting

### **Problema: Repositório não encontrado**

```bash
# Verificar se a chave GPG foi adicionada
ls -l /etc/apt/keyrings/docker.gpg

# Verificar se o repositório foi adicionado
cat /etc/apt/sources.list.d/docker.list

# Recriar se necessário (volte ao passo 3)
```

### **Problema: Versão 24.0.7 não aparece**

```bash
# Limpar cache do apt
sudo apt clean
sudo rm -rf /var/lib/apt/lists/*
sudo apt update

# Verificar novamente
apt-cache madison docker-ce | grep 24.0
```

### **Problema: Erro "Package not found"**

Você está usando Debian Testing/Unstable (Trixie). Use o repositório Bullseye:

```bash
# Remover repositório Trixie
sudo rm /etc/apt/sources.list.d/docker.list

# Adicionar Bullseye (conforme passo 3)
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
  bullseye stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
```

### **Problema: Docker não inicia**

```bash
# Ver logs do Docker
sudo journalctl -u docker.service -n 50 --no-pager

# Verificar configuração
sudo dockerd --validate

# Reiniciar serviço
sudo systemctl restart docker
```

---

## 📚 Recursos Adicionais

- [Documentação Oficial Docker](https://docs.docker.com/engine/install/debian/)
- [Docker Release Notes](https://docs.docker.com/engine/release-notes/24.0/)
- [Traefik Compatibility](https://doc.traefik.io/traefik/getting-started/install-traefik/)

---

## ⚠️ Nota Importante

**NÃO atualize** o Docker sem verificar compatibilidade com Traefik!

Versões testadas e compatíveis com este projeto:
- ✅ Docker 24.0.7 + Traefik 2.10.7 → **Funciona perfeitamente**
- ❌ Docker 29.x + Traefik 2.10.7 → **Erro: API 1.24 too old**
- ❌ Docker 28.x + Traefik 2.10.7 → **Possíveis problemas**

---

## 🎯 Próximos Passos

Após instalar o Docker 24.0.7, você pode:

1. **Inicializar Swarm:** `./swarm-init.sh`
2. **Fazer Deploy:** `./swarm-deploy.sh`
3. **Ver Logs:** `docker service logs -f traefik_traefik`

Consulte o [README.md](README.md) para instruções completas do projeto.
