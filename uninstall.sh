#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"

echo "=== Codex-GLM Proxy Uninstaller ==="
echo ""

echo "Stopping proxy..."
"$SCRIPT_DIR/proxy/stop.sh" 2>/dev/null || true

if [ "$OS" = "Darwin" ]; then
    PLIST="$HOME/Library/LaunchAgents/com.codex-glm.proxy.plist"
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "LaunchAgent removed"
elif [ "$OS" = "Linux" ]; then
    systemctl --user stop codex-glm-proxy.service 2>/dev/null || true
    systemctl --user disable codex-glm-proxy.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/codex-glm-proxy.service"
    systemctl --user daemon-reload 2>/dev/null || true
    echo "systemd service removed"
fi

rm -f /tmp/codex-glm-proxy.pid /tmp/codex-glm-proxy.log

echo ""
echo "Uninstall complete."
echo "Remove ~/.config/codex-glm/ manually if you want to delete API keys too."
