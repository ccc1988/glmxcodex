#!/usr/bin/env bash
set -e

PID_FILE="${PID_FILE:-/tmp/codex-glm-proxy.pid}"

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if kill "$PID" 2>/dev/null; then
        echo "Proxy stopped (PID: $PID)"
    else
        echo "Proxy not running (stale PID)"
    fi
    rm -f "$PID_FILE"
else
    echo "No PID file found. Try: pkill -f proxy.py"
fi
