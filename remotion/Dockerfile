FROM node:22-bookworm-slim

# Libs requeridas pelo Chromium Headless Shell (usado por @remotion/renderer).
# Lista conforme docs oficiais: https://www.remotion.dev/docs/docker
RUN apt-get update && apt-get install -y --no-install-recommends \
    libnss3 \
    libdbus-1-3 \
    libatk1.0-0 \
    libasound2 \
    libxrandr2 \
    libxkbcommon-dev \
    libxfixes3 \
    libxcomposite1 \
    libxdamage1 \
    libgbm-dev \
    libatk-bridge2.0-0 \
    libpango-1.0-0 \
    libcairo2 \
    libcups2 \
    fonts-liberation \
    fonts-noto-color-emoji \
    ca-certificates \
    tini \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json ./
RUN npm install --no-audit --no-fund

COPY tsconfig.json remotion.config.ts ./
COPY src ./src
COPY server ./server

# Pre-baixa o Chrome Headless Shell para nao atrasar o primeiro render
RUN npx remotion browser ensure

ENV NODE_ENV=production \
    PORT=3000 \
    NODE_OPTIONS=--max-old-space-size=4096

EXPOSE 3000

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["npm", "start"]
