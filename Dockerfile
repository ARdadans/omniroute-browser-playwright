# syntax=docker/dockerfile:1

FROM node:24-bookworm AS base

# Runtime deps + Playwright/Chromium support
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    openssl \
    dumb-init \
    xvfb \
    fonts-liberation \
    fonts-noto \
    fonts-noto-cjk \
    fonts-noto-color-emoji \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libcups2 \
    libdrm2 \
    libdbus-1-3 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libxkbcommon0 \
    libasound2 \
    libpangocairo-1.0-0 \
    libpango-1.0-0 \
    libcairo2 \
    libatspi2.0-0 \
    libgtk-3-0 \
    libglib2.0-0 \
    python3 \
    make \
    g++ \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ========== Builder ==========
FROM base AS builder

ARG OMNIROUTE_REPO_URL=https://github.com/diegosouzapw/OmniRoute.git
ARG OMNIROUTE_REF=release/v3.8.51

# Jangan set NODE_ENV=production di sini!
# Build butuh devDependencies (termasuk fumadocs-mdx)
ENV NEXT_TELEMETRY_DISABLED=1 \
    OMNIROUTE_MITM_STUB=1 \
    NODE_OPTIONS="--max-old-space-size=6144"

RUN git clone \
    --depth 1 \
    --branch "${OMNIROUTE_REF}" \
    "${OMNIROUTE_REPO_URL}" \
    /app

# Install SEMUA dependency (termasuk dev) karena build membutuhkan fumadocs-mdx dll
RUN npm ci --include=dev --legacy-peer-deps --no-audit --no-fund

# Rebuild native modules yang penting
RUN cd node_modules/better-sqlite3 \
    && npx node-gyp rebuild \
    || true

RUN npm run build

# ========== Runtime ==========
FROM base AS runner

ENV NODE_ENV=production \
    HOSTNAME=0.0.0.0 \
    PORT=20128 \
    DATA_DIR=/app/data \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    DISPLAY=:99 \
    NEXT_TELEMETRY_DISABLED=1 \
    OMNIROUTE_MITM_STUB=1 \
    NODE_OPTIONS="--max-old-space-size=1024"

WORKDIR /app

# Copy hasil build + node_modules production
COPY --from=builder /app/.build/next/standalone ./
COPY --from=builder /app/node_modules/better-sqlite3 ./node_modules/better-sqlite3
COPY --from=builder /app/package.json ./package.json

# Pastikan data dir ada
RUN mkdir -p /app/data /ms-playwright \
    && chown -R node:node /app /ms-playwright

# Install Chromium untuk Playwright (opsional, hanya jika butuh web providers)
USER root
RUN npx playwright install chromium --with-deps || true
USER node

COPY start.sh /usr/local/bin/docker-start.sh
RUN chmod +x /usr/local/bin/docker-start.sh

EXPOSE 20128

ENTRYPOINT ["dumb-init", "--"]
CMD ["/usr/local/bin/docker-start.sh"]