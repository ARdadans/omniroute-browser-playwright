# syntax=docker/dockerfile:1

FROM node:24-bookworm

LABEL org.opencontainers.image.title="omniroute" \
      org.opencontainers.image.description="OmniRoute - Free AI Gateway" \
      org.opencontainers.image.source="https://github.com/diegosouzapw/OmniRoute"

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
    && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production \
    HOSTNAME=0.0.0.0 \
    PORT=20128 \
    DATA_DIR=/app/data \
    PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
    DISPLAY=:99 \
    NEXT_TELEMETRY_DISABLED=1

WORKDIR /app

ARG OMNIROUTE_VERSION=

RUN set -eux; \
    if [ -n "$OMNIROUTE_VERSION" ]; then \
      npm install -g "omniroute@${OMNIROUTE_VERSION}" --legacy-peer-deps; \
    else \
      npm install -g omniroute --legacy-peer-deps; \
    fi; \
    OMNI_ROOT="$(npm root -g)/omniroute"; \
    cd "$OMNI_ROOT"; \
    npx playwright install chromium --with-deps; \
    mkdir -p /ms-playwright /app/data; \
    chown -R node:node /ms-playwright /app /home/node 2>/dev/null || true

USER node

EXPOSE 20128

ENTRYPOINT ["dumb-init", "--"]
CMD ["omniroute"]