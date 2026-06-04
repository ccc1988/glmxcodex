#!/bin/bash
PID_FILE="/tmp/codex-glm-proxy.pid"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        kill "$PID"
        echo "Proxy stopped (PID: $PID)"
    else
        echo "Proxy not running (stale PID file)"
    fi
    rm -f "$PID_FILE"
else
    pkill -f "proxy.py.*18765" 2>/dev/null && echo "Proxy stopped" || echo "Proxy not running"
fi
