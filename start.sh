#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${OMNIROUTE_REPO_URL:-https://github.com/diegosouzapw/OmniRoute.git}"
REPO_REF="${OMNIROUTE_REF:-release/v3.8.51}"

APP_DIR="${OMNIROUTE_APP_DIR:-.omniroute}"
IMAGE_NAME="${OMNIROUTE_IMAGE:-omniroute-local}"
CONTAINER_NAME="${OMNIROUTE_CONTAINER:-omniroute}"
PORT="${OMNIROUTE_PORT:-20128}"
DATA_VOLUME="${OMNIROUTE_DATA_VOLUME:-omniroute-data}"

wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-180}"

    echo "Waiting for ${host}:${port} ..."
    for ((i=1; i<=timeout; i++)); do
        if (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1; then
            echo "OmniRoute is ready: http://${host}:${port}"
            return 0
        fi
        sleep 1
    done
    echo "ERROR: OmniRoute did not start within ${timeout}s."
    return 1
}

native() {
    echo "========================================"
    echo " OmniRoute - Native"
    echo "========================================"

    if [[ ! -d "$APP_DIR/.git" ]]; then
        echo "[1/5] Cloning OmniRoute..."
        rm -rf "$APP_DIR"
        git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$APP_DIR"
    else
        echo "[1/5] OmniRoute already exists."
    fi

    cd "$APP_DIR"

    echo "[2/5] Installing dependencies (including devDeps for build)..."
    # Jangan set NODE_ENV=production sebelum install
    npm ci --include=dev --legacy-peer-deps --no-audit --no-fund

    echo "[3/5] Installing Playwright Chromium..."
    npx playwright install chromium || true

    echo "[4/5] Building OmniRoute..."
    npm run build

    echo "[5/5] Starting OmniRoute..."

    export HOSTNAME="${HOSTNAME:-0.0.0.0}"
    export PORT="$PORT"
    export DISPLAY="${DISPLAY:-:99}"
    export NODE_ENV=production

    # Virtual display
    if ! pgrep -f "Xvfb ${DISPLAY}" >/dev/null 2>&1; then
        echo "Starting Xvfb on ${DISPLAY}..."
        Xvfb "$DISPLAY" -screen 0 1920x1080x24 -ac +extension RANDR >/tmp/xvfb.log 2>&1 &
        sleep 2
    fi

    # Jalankan dari standalone jika ada, fallback ke npm start
    if [[ -f ".build/next/standalone/dev/run-standalone.mjs" ]]; then
        node .build/next/standalone/dev/run-standalone.mjs &
    else
        npm start &
    fi
    APP_PID=$!

    wait_for_port 127.0.0.1 "$PORT" 180

    echo
    echo "OmniRoute running."
    echo "PID : $APP_PID"
    echo "URL : http://127.0.0.1:$PORT"
    echo

    wait "$APP_PID"
}

docker_build() {
    echo "========================================"
    echo " Building Docker image"
    echo "========================================"

    docker build \
        --build-arg "OMNIROUTE_REPO_URL=$REPO_URL" \
        --build-arg "OMNIROUTE_REF=$REPO_REF" \
        -t "$IMAGE_NAME" \
        .
}

docker_run() {
    echo "========================================"
    echo " Starting OmniRoute Docker"
    echo "========================================"

    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "$PORT:20128" \
        -e "PORT=20128" \
        -e "HOSTNAME=0.0.0.0" \
        -e "DISPLAY=:99" \
        -e "NODE_ENV=production" \
        -v "$DATA_VOLUME:/app/data" \
        "$IMAGE_NAME"
}

docker() {
    docker_build
    docker_run
}

stop() {
    docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
}

logs() {
    docker logs -f "$CONTAINER_NAME"
}

status() {
    docker ps -a --filter "name=^${CONTAINER_NAME}$"
}

case "${1:-native}" in
    native)   native ;;
    docker)   docker ;;
    build)    docker_build ;;
    run)      docker_run ;;
    stop)     stop ;;
    logs)     logs ;;
    status)   status ;;
    restart)  stop; docker_run ;;
    *)
        echo "Usage:"
        echo "  ./start.sh              Native"
        echo "  ./start.sh native       Native"
        echo "  ./start.sh docker       Build + Run Docker"
        echo "  ./start.sh build        Docker build only"
        echo "  ./start.sh run          Docker run only"
        echo "  ./start.sh stop         Stop container"
        echo "  ./start.sh restart      Restart container"
        echo "  ./start.sh logs         Docker logs"
        echo "  ./start.sh status       Container status"
        exit 1
        ;;
esac