#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

echo ""
echo -e "${CYAN}卸载 Codex + GLM 一键配置${NC}"
echo ""

PLIST="$HOME/Library/LaunchAgents/com.litellm.proxy.plist"

if [[ -f "$PLIST" ]] && launchctl list com.litellm.proxy &>/dev/null; then
    info "停止 LaunchAgent 服务..."
    launchctl unload "$PLIST" 2>/dev/null
    rm -f "$PLIST"
    success "LaunchAgent 已移除"
fi

if lsof -i :4000 -t &>/dev/null; then
    info "停止 litellm 进程..."
    lsof -i :4000 -t | xargs kill 2>/dev/null
    sleep 1
    success "litellm 已停止"
fi

read -p "是否删除配置文件? [y/N]: " del_config
if [[ "$del_config" =~ ^[Yy] ]]; then
    BACKUP_DIR="$HOME/.codex-glm-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    for f in "$HOME/.claude/litellm-config.yaml" "$HOME/.codex/config.toml" "$HOME/.codex/auth.json"; do
        if [[ -f "$f" ]]; then
            cp "$f" "$BACKUP_DIR/"
            rm -f "$f"
            info "备份并删除: $(basename $f)"
        fi
    done
    success "配置文件已备份到 $BACKUP_DIR 并删除"
else
    info "保留配置文件"
fi

rm -f "$HOME/start_litellm.sh"
rm -f "$HOME/stop_litellm.sh"
success "辅助脚本已移除"

echo ""
success "卸载完成！"
echo "  注意: litellm Python 包未被卸载，如需卸载请运行: pip uninstall litellm"
echo ""
