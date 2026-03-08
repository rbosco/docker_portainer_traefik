#!/bin/bash
set -e

echo "================================================"
echo "  Remotion Studio"
echo "================================================"

# Verificar se existe package.json no projeto
if [ ! -f "/app/package.json" ]; then
    echo ""
    echo "AVISO: Nenhum projeto Remotion encontrado em /app."
    echo "Coloque seu projeto Remotion em ./remotion/project/"
    echo ""
    echo "Exemplo de estrutura esperada:"
    echo "  remotion/project/"
    echo "  ├── package.json"
    echo "  ├── src/"
    echo "  │   ├── index.ts"
    echo "  │   └── Root.tsx"
    echo "  └── remotion.config.ts"
    echo ""
    echo "Aguardando projeto... (verificando a cada 30s)"
    while [ ! -f "/app/package.json" ]; do
        sleep 30
    done
fi

echo "Projeto encontrado. Instalando dependências..."
npm install --legacy-peer-deps

echo "Iniciando Remotion Studio na porta 3000..."
exec npx remotion studio --port 3000 --log info
