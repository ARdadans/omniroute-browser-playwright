# ================= STAGE 1: BUILD =================
FROM node:24-bookworm AS builder

ARG OMNIROUTE_REPO_URL=https://github.com/diegosouzapw/OmniRoute.git
ARG OMNIROUTE_REF=release/v3.8.51

# PENTING: jangan set NODE_ENV=production di sini,
# supaya devDependencies (mis. fumadocs-mdx) ikut ke-install saat build.
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    openssl \
    curl \
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
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable && corepack prepare pnpm@latest --activate

RUN git clone \
    --depth 1 \
    --branch "${OMNIROUTE_REF}" \
    "${OMNIROUTE_REPO_URL}" \
    /app

# Install SEMUA dependency (prod + dev) — NODE_ENV belum "production"
RUN pnpm install --frozen-lockfile

RUN pnpm exec playwright install chromium

RUN pnpm run build

# ================= STAGE 2: RUNTIME =================
FROM node:24-bookworm

ENV NODE_ENV=production \
    HOSTNAME=0.0.0.0 \
    PORT=20128 \
    DATA_DIR=/app/data \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    DISPLAY=:99 \
    COREPACK_ENABLE_DOWNLOAD_PROMPT=0

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
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
    && rm -rf /var/lib/apt/lists/*

# Bawa hasil build + node_modules + browser chromium dari stage builder
COPY --from=builder /app /app
COPY --from=builder /ms-playwright /ms-playwright

RUN mkdir -p /app/data \
    && chown -R node:node /app /ms-playwright

COPY start.sh /usr/local/bin/docker-start.sh
RUN chmod +x /usr/local/bin/docker-start.sh

USER node

EXPOSE 20128

ENTRYPOINT ["dumb-init", "--"]

CMD ["/usr/local/bin/docker-start.sh"]