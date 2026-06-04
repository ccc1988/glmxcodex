#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="${LOG_FILE:-/tmp/codex-glm-proxy.log}"
PID_FILE="${PID_FILE:-/tmp/codex-glm-proxy.pid}"
PROXY_PORT="${PROXY_PORT:-18765}"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill -0 "$PID" 2>/dev/null; then
        echo "Proxy already running (PID: $PID)"
        exit 0
    fi
fi

nohup python3 "$SCRIPT_DIR/proxy.py" > "$LOG_FILE" 2>&1 &
PID=$!
echo $PID > "$PID_FILE"
sleep 1

if kill -0 "$PID" 2>/dev/null; then
    echo "Proxy started (PID: $PID, port: $PROXY_PORT)"
else
    echo "ERROR: Proxy failed to start. Log: $LOG_FILE"
    cat "$LOG_FILE"
    rm -f "$PID_FILE"
    exit 1
fi
