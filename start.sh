#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# OmniRoute launcher
# Native  → npm install -g + Playwright Chromium
# Docker  → build local image atau pakai official -web
# ============================================================

IMAGE_NAME="${OMNIROUTE_IMAGE:-omniroute-local}"
CONTAINER_NAME="${OMNIROUTE_CONTAINER:-omniroute}"
PORT="${OMNIROUTE_PORT:-20128}"
DATA_VOLUME="${OMNIROUTE_DATA_VOLUME:-omniroute-data}"
VERSION="${OMNIROUTE_VERSION:-}"          # optional pin, e.g. 3.8.51

# Official image (fallback kalau tidak build sendiri)
OFFICIAL_IMAGE="${OMNIROUTE_OFFICIAL_IMAGE:-diegosouzapw/omniroute:latest-web}"

wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-120}"

    echo "Waiting for ${host}:${port} ..."
    for ((i=1; i<=timeout; i++)); do
        if (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1; then
            echo "OmniRoute is ready → http://${host}:${port}"
            return 0
        fi
        sleep 1
    done
    echo "ERROR: OmniRoute did not become ready within ${timeout}s"
    return 1
}

# ====================== Native ======================
native() {
    echo "========================================"
    echo " OmniRoute - Native (npm global)"
    echo "========================================"

    # 1. Install / update OmniRoute globally
    echo "[1/3] Installing omniroute globally..."
    if [[ -n "$VERSION" ]]; then
        npm install -g "omniroute@${VERSION}" --legacy-peer-deps
    else
        npm install -g omniroute --legacy-peer-deps
    fi

    # 2. Install Playwright Chromium + system deps
    #    (sesuai TROUBLESHOOTING.md – Gemini Web & Playwright)
    echo "[2/3] Installing Playwright Chromium + deps..."
    local OMNI_ROOT
    OMNI_ROOT="$(npm root -g)/omniroute"

    if [[ -d "$OMNI_ROOT" ]]; then
        (
            cd "$OMNI_ROOT"
            npx playwright install chromium
            # install-deps menarik libnss3, libgbm1, dll (penting di Debian/Ubuntu)
            npx playwright install-deps chromium || true
        )
    else
        echo "WARNING: global omniroute directory not found, trying fallback..."
        npx playwright install chromium || true
        npx playwright install-deps chromium || true
    fi

    # Optional headful (Xvfb) – aktifkan dengan OMNIROUTE_HEADFUL=1
    if [[ "${OMNIROUTE_HEADFUL:-0}" == "1" ]]; then
        export DISPLAY="${DISPLAY:-:99}"
        if ! pgrep -f "Xvfb ${DISPLAY}" >/dev/null 2>&1; then
            echo "Starting Xvfb on ${DISPLAY}..."
            Xvfb "$DISPLAY" \
                -screen 0 1920x1080x24 \
                -ac \
                +extension RANDR \
                >/tmp/xvfb-omniroute.log 2>&1 &
            sleep 1
        fi
    fi

    # 3. Start
    echo "[3/3] Starting OmniRoute..."
    export HOSTNAME="${HOSTNAME:-0.0.0.0}"
    export PORT="$PORT"

    exec omniroute
}

# ====================== Docker ======================
docker_build() {
    echo "========================================"
    echo " Building Docker image: $IMAGE_NAME"
    echo "========================================"

    local build_args=()
    if [[ -n "$VERSION" ]]; then
        build_args+=(--build-arg "OMNIROUTE_VERSION=$VERSION")
    fi

    docker build \
        "${build_args[@]}" \
        -t "$IMAGE_NAME" \
        .
}

docker_run() {
    echo "========================================"
    echo " Starting OmniRoute Docker"
    echo " Image : $IMAGE_NAME"
    echo "========================================"

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --stop-timeout 40 \
        -p "${PORT}:20128" \
        -e "PORT=20128" \
        -e "HOSTNAME=0.0.0.0" \
        -e "DISPLAY=:99" \
        -v "${DATA_VOLUME}:/app/data" \
        "$IMAGE_NAME"

    echo
    echo "Container started."
    echo "URL  : http://127.0.0.1:${PORT}"
    echo "Logs : ./start.sh logs"
    echo
}

# Jalankan official image -web (paling mudah, sudah ada Chromium)
docker_official() {
    echo "========================================"
    echo " Using official image: $OFFICIAL_IMAGE"
    echo "========================================"

    docker pull "$OFFICIAL_IMAGE"

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        --stop-timeout 40 \
        -p "${PORT}:20128" \
        -e "PORT=20128" \
        -e "HOSTNAME=0.0.0.0" \
        -v "${DATA_VOLUME}:/app/data" \
        "$OFFICIAL_IMAGE"

    echo
    echo "Container started (official -web)."
    echo "URL  : http://127.0.0.1:${PORT}"
    echo
}

docker() {
    docker_build
    docker_run
}

stop() {
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
    echo "Container stopped."
}

logs() {
    docker logs -f "$CONTAINER_NAME"
}

status() {
    docker ps -a --filter "name=^${CONTAINER_NAME}$"
}

# ====================== Entrypoint di dalam container ======================
# Dipanggil oleh Dockerfile (CMD)
container_start() {
    # Xvfb opsional di dalam container
    if [[ "${OMNIROUTE_HEADFUL:-0}" == "1" ]]; then
        export DISPLAY="${DISPLAY:-:99}"
        if ! pgrep -f "Xvfb ${DISPLAY}" >/dev/null 2>&1; then
            Xvfb "$DISPLAY" -screen 0 1920x1080x24 -ac +extension RANDR \
                >/tmp/xvfb.log 2>&1 &
            sleep 1
        fi
    fi

    export HOSTNAME="${HOSTNAME:-0.0.0.0}"
    export PORT="${PORT:-20128}"

    exec omniroute
}

# ====================== CLI ======================
case "${1:-native}" in
    native)
        native
        ;;
    docker)
        docker
        ;;
    build)
        docker_build
        ;;
    run)
        docker_run
        ;;
    official)
        docker_official
        ;;
    stop)
        stop
        ;;
    logs)
        logs
        ;;
    status)
        status
        ;;
    restart)
        stop
        docker_run
        ;;
    # Dipakai oleh Dockerfile
    container)
        container_start
        ;;
    *)
        echo "Usage:"
        echo "  ./start.sh              Native (npm global + Chromium)"
        echo "  ./start.sh native       Native"
        echo "  ./start.sh docker       Build Dockerfile lokal + run"
        echo "  ./start.sh build        Build image saja"
        echo "  ./start.sh run          Run image lokal"
        echo "  ./start.sh official     Pakai image resmi diegosouzapw/omniroute:*-web"
        echo "  ./start.sh stop         Stop container"
        echo "  ./start.sh restart      Restart"
        echo "  ./start.sh logs         Follow logs"
        echo "  ./start.sh status       Status container"
        echo
        echo "Environment:"
        echo "  OMNIROUTE_PORT=20128"
        echo "  OMNIROUTE_VERSION=3.8.51"
        echo "  OMNIROUTE_IMAGE=omniroute-local"
        echo "  OMNIROUTE_HEADFUL=1              # aktifkan Xvfb"
        exit 1
        ;;
esac