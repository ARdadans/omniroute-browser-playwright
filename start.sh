#!/usr/bin/env bash
set -Eeuo pipefail

PORT="${OMNIROUTE_PORT:-20128}"
VERSION="${OMNIROUTE_VERSION:-}"

echo "========================================"
echo " OmniRoute - Native"
echo "========================================"

echo "[1/3] Installing omniroute globally..."
if [[ -n "$VERSION" ]]; then
    npm install -g "omniroute@${VERSION}" --legacy-peer-deps
else
    npm install -g omniroute --legacy-peer-deps
fi

echo "[2/3] Installing Playwright Chromium + deps..."
OMNI_ROOT="$(npm root -g)/omniroute"

if [[ -d "$OMNI_ROOT" ]]; then
    (
        cd "$OMNI_ROOT"
        npx playwright install chromium --with-deps
    )
else
    echo "WARNING: global omniroute directory not found, trying fallback..."
    npx playwright install chromium --with-deps || true
fi

if [[ "${OMNIROUTE_HEADFUL:-0}" == "1" ]]; then
    export DISPLAY="${DISPLAY:-:99}"
    if ! pgrep -f "Xvfb ${DISPLAY}" >/dev/null 2>&1; then
        echo "Starting Xvfb on ${DISPLAY}..."
        Xvfb "$DISPLAY" -screen 0 1920x1080x24 -ac +extension RANDR \
            >/tmp/xvfb-omniroute.log 2>&1 &
        sleep 1
    fi
fi

echo "[3/3] Starting OmniRoute..."
export HOSTNAME="${HOSTNAME:-0.0.0.0}"
export PORT

exec omniroute