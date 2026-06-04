#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="/tmp/codex-glm-proxy.log"
PID_FILE="/tmp/codex-glm-proxy.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "Proxy already running (PID: $PID)"
        exit 0
    fi
fi

export GLM_API_KEY="${GLM_API_KEY:-$(python3 -c "import json; print(json.load(open('$HOME/.codex/auth.json')).get('OPENAI_API_KEY',''))" 2>/dev/null)}"
export GLM_API_BASE="${GLM_API_BASE:-https://open.bigmodel.cn/api/coding/paas/v4}"
export PROXY_PORT="${PROXY_PORT:-18765}"

if [ -z "$GLM_API_KEY" ]; then
    echo "Error: GLM_API_KEY not set and not found in ~/.codex/auth.json"
    exit 1
fi

echo "Starting Codex-GLM Proxy on port $PROXY_PORT..."
nohup python3 "$SCRIPT_DIR/proxy.py" > "$LOG_FILE" 2>&1 &
PID=$!
echo $PID > "$PID_FILE"
sleep 2

if curl -s "http://localhost:$PROXY_PORT/health" > /dev/null 2>&1; then
    echo "Proxy started successfully (PID: $PID)"
    echo "  Health check: http://localhost:$PROXY_PORT/health"
    echo "  Log file: $LOG_FILE"
else
    echo "Proxy failed to start. Check log: $LOG_FILE"
    cat "$LOG_FILE"
    rm -f "$PID_FILE"
    exit 1
fi
