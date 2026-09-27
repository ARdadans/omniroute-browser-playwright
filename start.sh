#!/usr/bin/env bash
set -Eeuo pipefail

# ============================================================
# OmniRoute Wrapper
#
# Usage:
#   ./start.sh              Native mode
#   ./start.sh local        Native mode
#   ./start.sh docker       Docker mode
#   ./start.sh build        Build Docker image
#   ./start.sh stop         Stop Docker
#   ./start.sh restart      Restart Docker
#   ./start.sh logs         Docker logs
#   ./start.sh status       Docker status
#   ./start.sh shell        Docker shell
#   ./start.sh clean        Remove generated source/cache
# ============================================================

REPO_URL="${OMNIROUTE_REPO_URL:-https://github.com/diegosouzapw/OmniRoute.git}"
REPO_REF="${OMNIROUTE_REF:-release/v3.8.51}"

APP_DIR="${OMNIROUTE_APP_DIR:-.omniroute}"
IMAGE_NAME="${OMNIROUTE_IMAGE:-omniroute-local}"
CONTAINER_NAME="${OMNIROUTE_CONTAINER:-omniroute}"
VOLUME_NAME="${OMNIROUTE_VOLUME:-omniroute-data}"

HOST_PORT="${HOST_PORT:-20128}"
CONTAINER_PORT="${CONTAINER_PORT:-20128}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

info() { printf '\033[1;34m[INFO]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ OK ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# ============================================================
# Generate secret
# ============================================================

generate_secret() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -hex 32
    elif command -v node >/dev/null 2>&1; then
        node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
    else
        die "openssl atau Node.js diperlukan untuk membuat secret."
    fi
}

JWT_SECRET="${JWT_SECRET:-$(generate_secret)}"
API_KEY_SECRET="${API_KEY_SECRET:-$(generate_secret)}"
INITIAL_PASSWORD="${INITIAL_PASSWORD:-admin12345}"

# ============================================================
# Clone / update OmniRoute source
# ============================================================

prepare_source() {
    if [ ! -d "$APP_DIR/.git" ]; then
        info "OmniRoute source belum tersedia."
        info "Cloning: $REPO_URL"
        info "Ref: $REPO_REF"

        rm -rf "$APP_DIR"

        git clone \
            --depth 1 \
            --branch "$REPO_REF" \
            "$REPO_URL" \
            "$APP_DIR"

        ok "OmniRoute source berhasil di-clone."
    else
        ok "OmniRoute source sudah tersedia."

        if [ "${OMNIROUTE_UPDATE:-0}" = "1" ]; then
            info "Updating OmniRoute source..."

            git -C "$APP_DIR" fetch \
                --depth 1 \
                origin \
                "$REPO_REF"

            git -C "$APP_DIR" checkout -f "$REPO_REF"

            ok "OmniRoute source updated."
        fi
    fi

    [ -f "$APP_DIR/package.json" ] \
        || die "package.json tidak ditemukan di OmniRoute source."

    ok "package.json ditemukan."
}

# ============================================================
# Wait for port
# ============================================================

wait_for_port() {
    local host="$1"
    local port="$2"
    local timeout="${3:-180}"

    info "Menunggu OmniRoute membuka port ${host}:${port}..."

    local start
    start="$(date +%s)"

    while true; do
        if (echo >/dev/tcp/"$host"/"$port") >/dev/null 2>&1; then
            ok "OmniRoute sudah listening pada ${host}:${port}"
            return 0
        fi

        local now
        now="$(date +%s)"

        if (( now - start >= timeout )); then
            err "Timeout menunggu port ${port}."
            return 1
        fi

        sleep 1
    done
}

# ============================================================
# Native
# ============================================================

run_native() {
    command -v git >/dev/null 2>&1 \
        || die "Git tidak ditemukan."

    command -v node >/dev/null 2>&1 \
        || die "Node.js tidak ditemukan."

    command -v npm >/dev/null 2>&1 \
        || die "npm tidak ditemukan."

    echo
    echo "================================================"
    echo " OmniRoute - Native"
    echo "================================================"

    ok "Node: $(node --version)"
    ok "npm : $(npm --version)"

    prepare_source

    cd "$APP_DIR"

    # --------------------------------------------------------
    # Dependencies
    # --------------------------------------------------------

    if [ -f package-lock.json ]; then
        info "Installing npm dependencies with npm ci..."
        npm ci
    else
        info "package-lock.json tidak tersedia."
        info "Installing npm dependencies with npm install..."
        npm install
    fi

    ok "npm dependencies installed."

    # --------------------------------------------------------
    # Playwright
    # --------------------------------------------------------

    if node -e "require('playwright')" >/dev/null 2>&1; then
        ok "Playwright package tersedia."
    else
        die "Playwright package tidak ditemukan di dependency OmniRoute."
    fi

    info "Installing/checking Chromium..."

    npx playwright install chromium

    ok "Chromium siap."

    # --------------------------------------------------------
    # Build
    # --------------------------------------------------------

    info "Building OmniRoute..."
    npm run build

    ok "OmniRoute build selesai."

    # --------------------------------------------------------
    # Runtime environment
    # --------------------------------------------------------

    export NODE_ENV="${NODE_ENV:-production}"
    export HOSTNAME="${HOSTNAME:-0.0.0.0}"
    export PORT="$CONTAINER_PORT"
    export DATA_DIR="${DATA_DIR:-$SCRIPT_DIR/$APP_DIR/data}"

    mkdir -p "$DATA_DIR"

    info "HOSTNAME : $HOSTNAME"
    info "PORT     : $PORT"
    info "DATA_DIR : $DATA_DIR"

    echo
    echo "================================================"
    echo " Starting OmniRoute"
    echo "================================================"

    npm start &
    APP_PID=$!

    trap '
        echo
        info "Stopping OmniRoute..."
        kill "$APP_PID" 2>/dev/null || true
        wait "$APP_PID" 2>/dev/null || true
    ' EXIT INT TERM

    if ! wait_for_port "127.0.0.1" "$CONTAINER_PORT" 180; then
        echo
        err "OmniRoute gagal start."

        if kill -0 "$APP_PID" 2>/dev/null; then
            warn "Process masih berjalan tetapi port belum terbuka."
        else
            err "Process OmniRoute sudah berhenti."
        fi

        exit 1
    fi

    echo
    echo "================================================"
    echo " OmniRoute READY"
    echo "================================================"
    echo
    echo " URL:"
    echo "   http://127.0.0.1:${CONTAINER_PORT}"
    echo
    echo " Source:"
    echo "   ${SCRIPT_DIR}/${APP_DIR}"
    echo
    echo " Press Ctrl+C to stop."
    echo

    wait "$APP_PID"
}

# ============================================================
# Docker check
# ============================================================

check_docker() {
    command -v docker >/dev/null 2>&1 \
        || die "Docker tidak ditemukan."

    docker info >/dev/null 2>&1 \
        || die "Docker daemon tidak berjalan."

    ok "Docker tersedia."
}

# ============================================================
# Docker build
# ============================================================

docker_build() {
    check_docker

    echo
    echo "================================================"
    echo " Building OmniRoute Docker Image"
    echo "================================================"

    docker build \
        --progress=plain \
        --build-arg OMNIROUTE_REPO_URL="$REPO_URL" \
        --build-arg OMNIROUTE_REF="$REPO_REF" \
        -t "$IMAGE_NAME" \
        .

    ok "Image ready: $IMAGE_NAME"
}

# ============================================================
# Docker run
# ============================================================

docker_run() {
    check_docker

    if ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        info "Docker image belum ada."
        docker_build
    fi

    if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
        info "Removing existing container..."
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi

    if ! docker volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
        info "Creating persistent volume..."
        docker volume create "$VOLUME_NAME" >/dev/null
    fi

    echo
    echo "================================================"
    echo " Starting OmniRoute Docker"
    echo "================================================"

    docker run \
        --name "$CONTAINER_NAME" \
        --restart unless-stopped \
        -p "${HOST_PORT}:${CONTAINER_PORT}" \
        -e NODE_ENV=production \
        -e HOSTNAME=0.0.0.0 \
        -e PORT="$CONTAINER_PORT" \
        -e DATA_DIR=/app/data \
        -e PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
        -e JWT_SECRET="$JWT_SECRET" \
        -e API_KEY_SECRET="$API_KEY_SECRET" \
        -e INITIAL_PASSWORD="$INITIAL_PASSWORD" \
        -v "${VOLUME_NAME}:/app/data" \
        -d \
        "$IMAGE_NAME" >/dev/null

    ok "Container started."

    if ! wait_for_port "127.0.0.1" "$HOST_PORT" 180; then
        echo
        err "OmniRoute tidak berhasil membuka port ${HOST_PORT}."

        echo
        echo "---------------- Docker Logs ----------------"
        docker logs "$CONTAINER_NAME" || true
        echo "----------------------------------------------"

        exit 1
    fi

    echo
    echo "================================================"
    echo " OmniRoute READY"
    echo "================================================"
    echo
    echo " URL:"
    echo "   http://127.0.0.1:${HOST_PORT}"
    echo
    echo " Container:"
    echo "   ${CONTAINER_NAME}"
    echo
    echo " Port:"
    echo "   ${HOST_PORT}:${CONTAINER_PORT}"
    echo
}

# ============================================================
# Docker commands
# ============================================================

docker_stop() {
    check_docker

    if docker container inspect "$CONTAINER_NAME" >/dev/null 2>&1; then
        docker rm -f "$CONTAINER_NAME"
        ok "OmniRoute stopped."
    else
        info "Container tidak ditemukan."
    fi
}

docker_restart() {
    docker_stop
    docker_run
}

docker_logs() {
    check_docker
    docker logs -f --tail 200 "$CONTAINER_NAME"
}

docker_status() {
    check_docker

    docker ps \
        -a \
        --filter "name=^${CONTAINER_NAME}$" \
        --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
}

docker_shell() {
    check_docker
    docker exec -it "$CONTAINER_NAME" bash
}

clean() {
    info "Removing generated OmniRoute source..."
    rm -rf "$APP_DIR"
    ok "Generated source removed."

    info "Docker image and volume are NOT removed."
    info "Use Docker commands manually if you want to remove them."
}

# ============================================================
# Help
# ============================================================

help() {
    cat <<EOF

OmniRoute Wrapper

Usage:

  ./start.sh
      Run OmniRoute natively.

  ./start.sh local
      Run OmniRoute natively.

  ./start.sh docker
      Build Docker image if necessary and run OmniRoute.

  ./start.sh build
      Build Docker image only.

  ./start.sh stop
      Stop/remove Docker container.

  ./start.sh restart
      Restart Docker container.

  ./start.sh logs
      Follow Docker logs.

  ./start.sh status
      Show Docker container status.

  ./start.sh shell
      Open shell inside Docker container.

  ./start.sh clean
      Remove generated local OmniRoute source.

Environment:

  OMNIROUTE_REPO_URL
  OMNIROUTE_REF
  HOST_PORT
  JWT_SECRET
  API_KEY_SECRET
  INITIAL_PASSWORD

Examples:

  ./start.sh

  ./start.sh docker

  HOST_PORT=3000 ./start.sh docker

  OMNIROUTE_REF=release/v3.8.51 ./start.sh docker

EOF
}

# ============================================================
# Main
# ============================================================

case "${1:-local}" in
    local|native)
        run_native
        ;;

    docker)
        docker_run
        ;;

    build)
        docker_build
        ;;

    stop)
        docker_stop
        ;;

    restart)
        docker_restart
        ;;

    logs)
        docker_logs
        ;;

    status)
        docker_status
        ;;

    shell)
        docker_shell
        ;;

    clean)
        clean
        ;;

    help|-h|--help)
        help
        ;;

    *)
        err "Unknown command: $1"
        help
        exit 1
        ;;
esac