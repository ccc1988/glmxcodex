#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO ]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK   ]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN ]${NC} $1"; }

CONFIG_DIR="$HOME/.config/codex-glm"
CODEC_CONFIG="$HOME/.codex/config.toml"
CATALOG_FILE="$HOME/.codex/codex-glm-model-catalog.json"

CLEAN_ALL=false
while [[ $# -gt 0 ]]; do case "$1" in
    --all|-a) CLEAN_ALL=true; shift ;;
    *) echo "Unknown: $1"; echo "Usage: ./uninstall.sh [--all|-a]"; exit 1 ;;
esac; done

echo "=== Codex-GLM Proxy Uninstaller ==="
echo ""

echo "Stopping proxy..."
"$SCRIPT_DIR/proxy/stop.sh" 2>/dev/null || true

if [ "$OS" = "Darwin" ]; then
    PLIST="$HOME/Library/LaunchAgents/com.codex-glm.proxy.plist"
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    ok "LaunchAgent removed"
elif [ "$OS" = "Linux" ]; then
    systemctl --user stop codex-glm-proxy.service 2>/dev/null || true
    systemctl --user disable codex-glm-proxy.service 2>/dev/null || true
    rm -f "$HOME/.config/systemd/user/codex-glm-proxy.service"
    systemctl --user daemon-reload 2>/dev/null || true
    ok "systemd service removed"
fi

rm -f /tmp/codex-glm-proxy.pid /tmp/codex-glm-proxy.log

echo ""

DELETE_KEYS="$CLEAN_ALL"
if [ "$CLEAN_ALL" != true ] && [ -d "$CONFIG_DIR" ]; then
    echo "API keys are stored in: $CONFIG_DIR"
    read -rp "  Delete API keys and all config? [y/N]: " yn
    case "$yn" in [Yy]|[Yy][Ee][Ss]) DELETE_KEYS=true ;; *) DELETE_KEYS=false ;; esac
fi

if [ "$DELETE_KEYS" = true ]; then
    rm -rf "$CONFIG_DIR"
    ok "Deleted: $CONFIG_DIR (API keys removed)"
    rm -f "$CATALOG_FILE"
    ok "Deleted: $CATALOG_FILE"
else
    info "Kept: $CONFIG_DIR (API keys preserved for reinstall)"
fi

echo ""
echo "Uninstall complete."
