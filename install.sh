#!/usr/bin/env bash
set -euo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"
PROXY_DIR="$SCRIPT_DIR/proxy"
CONFIG_DIR="$HOME/.config/codex-glm"
mkdir -p "$CONFIG_DIR"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  Codex Multi-Backend Proxy Installer${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

if ! command -v python3 &>/dev/null; then
    err "Python 3 is required but not found. Install it first: https://python.org"
fi

info "OS detected: $OS"
info "Python: $(python3 --version)"

# === Collect API Keys ===
echo ""
echo -e "${YELLOW}--- API Key Configuration ---${NC}"
echo "Enter your API keys (leave blank to skip a provider):"
echo ""

read -rp "  GLM API Key (智谱): " GLM_KEY
read -rp "  DeepSeek API Key:      " DEEPSEEK_KEY
read -rp "  OpenAI API Key:        " OPENAI_KEY

# Build proxy config JSON
python3 -c "
import json, os
cfg_path = os.path.expanduser('$CONFIG_DIR/proxy-config.json')
cfg = {'backends': {}}
if '$GLM_KEY':    cfg['backends']['glm'] = {'api_key': '$GLM_KEY'}
if '$DEEPSEEK_KEY': cfg['backends']['deepseek'] = {'api_key': '$DEEPSEEK_KEY', 'api_base': 'https://api.deepseek.com/v1'}
if '$OPENAI_KEY':  cfg['backends']['openai'] = {'api_key': '$OPENAI_KEY', 'api_base': 'https://api.openai.com/v1'}
with open(cfg_path, 'w') as f:
    json.dump(cfg, f, indent=2)
print('Config saved to: ' + cfg_path)
print('Backends: ' + str([k for k,v in cfg['backends'].items() if v.get('api_key')]))
" || err "Failed to write proxy config"

echo ""
ok "API keys configured"

# === Generate model catalog ===
python3 -c "
import json, os
models = [
    {'id': 'glm-5.1', 'display_name': 'GLM-5.1', 'provider': 'zhipu', 'slug': 'glm-5.1',
     'visibility': 'list', 'supported_in_api': True, 'context_window': 200000, 'max_context_window': 200000,
     'default_reasoning_level': 'medium', 'supported_reasoning_levels': [
         {'effort': 'low', 'description': 'Fast'}, {'effort': 'medium', 'description': 'Balanced'}, {'effort': 'high', 'description': 'Deep'}
     ], 'description': 'GLM-5.1 (智谱 AI)', 'input_modalities': ['text', 'image'],
     'supports_parallel_tool_calls': True, 'apply_patch_tool_type': 'freeform', 'shell_type': 'shell_command',
     'experimental_supported_tools': [], 'additional_speed_tiers': [], 'service_tiers': [],
     'supports_search_tool': False, 'web_search_tool_type': 'text_and_image',
     'supports_image_detail_original': True, 'supports_reasoning_summaries': True,
     'support_verbosity': True, 'default_reasoning_summary': 'none', 'default_verbosity': 'low',
     'effective_context_window_percent': 95, 'truncation_policy': {'mode': 'tokens', 'limit': 10000},
     'model_messages': {'instructions_template': 'You are Codex, a coding agent.'},
     'base_instructions': 'You are Codex, a coding agent powered by GLM (智谱 AI).',
     'availability_nux': None, 'upgrade': None, 'priority': 1000},
]
if '$DEEPSEEK_KEY':
    models.append({
        'id': 'deepseek-chat', 'display_name': 'DeepSeek Chat', 'provider': 'deepseek', 'slug': 'deepseek-chat',
        'visibility': 'list', 'supported_in_api': True, 'context_window': 128000, 'max_context_window': 128000,
        'default_reasoning_level': 'medium', 'supported_reasoning_levels': [{'effort': 'medium'}],
        'description': 'DeepSeek Chat', 'input_modalities': ['text'],
        'supports_parallel_tool_calls': True, 'apply_patch_tool_type': 'freeform', 'shell_type': 'shell_command',
        'experimental_supported_tools': [], 'additional_speed_tiers': [], 'service_tiers': [],
        'supports_search_tool': False, 'web_search_tool_type': 'text_and_image',
        'supports_image_detail_original': False, 'supports_reasoning_summaries': True,
        'support_verbosity': True, 'default_reasoning_summary': 'none', 'default_verbosity': 'low',
        'effective_context_window_percent': 95, 'truncation_policy': {'mode': 'tokens', 'limit': 10000},
        'model_messages': {'instructions_template': 'You are Codex, a coding agent.'},
        'base_instructions': 'You are Codex, a coding agent powered by DeepSeek.',
        'availability_nux': None, 'upgrade': None, 'priority': 900},
    )
catalog_path = os.path.expanduser('$HOME/.codex/cc-switch-model-catalog.json')
os.makedirs(os.path.dirname(catalog_path), exist_ok=True)
with open(catalog_path, 'w') as f:
    json.dump({'models': models}, f, indent=2, ensure_ascii=False)
print('Model catalog saved to: ' + catalog_path)
" || err "Failed to generate model catalog"

ok "Model catalog generated"

# === Auto-start setup ===
echo ""
info "Setting up auto-start..."
AUTO_START_SUCCESS=false

if [ "$OS" = "Darwin" ]; then
    PLIST="$HOME/Library/LaunchAgents/com.codex-glm.proxy.plist"
    mkdir -p "$HOME/Library/LaunchAgents"

    cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.codex-glm.proxy</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which python3)</string>
        <string>$PROXY_DIR/proxy.py</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/codex-glm-proxy.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/codex-glm-proxy.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>CONFIG_DIR</key>
        <string>$CONFIG_DIR</string>
    </dict>
</dict>
</plist>
PLISTEOF

    launchctl unload "$PLIST" 2>/dev/null || true
    launchctl load "$PLIST" 2>/dev/null && AUTO_START_SUCCESS=true
    ok "LaunchAgent installed"

elif [ "$OS" = "Linux" ]; then
    SERVICE_FILE="$HOME/.config/systemd/user/codex-glm-proxy.service"
    mkdir -p "$(dirname "$SERVICE_FILE")"

    cat > "$SERVICE_FILE" << SERVICEEOF
[Unit]
Description=Codex Multi-Backend Proxy
After=network.target

[Service]
ExecStart=$(which python3) $PROXY_DIR/proxy.py
Environment=CONFIG_DIR=$CONFIG_DIR
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
SERVICEEOF

    systemctl --user daemon-reload 2>/dev/null
    systemctl --user enable codex-glm-proxy.service 2>/dev/null
    systemctl --user start codex-glm-proxy.service 2>/dev/null && AUTO_START_SUCCESS=true
    ok "systemd service installed"

else
    warn "Auto-start not supported on $OS. Start manually: python3 $PROXY_DIR/proxy.py &"
fi

if [ "$AUTO_START_SUCCESS" = true ]; then
    ok "Auto-start configured"
fi

# === Start proxy now ===
echo ""
info "Starting proxy..."
"$PROXY_DIR/start.sh" 2>/dev/null || warn "Proxy start script failed, trying directly: python3 $PROXY_DIR/proxy.py &"

sleep 2
if curl -s http://localhost:18765/health > /dev/null 2>&1; then
    ok "Proxy running on http://localhost:18765"
    HEALTH=$(curl -s http://localhost:18765/health)
    echo "  Health: $HEALTH"
else
    warn "Proxy health check failed. Check logs: /tmp/codex-glm-proxy.log"
fi

# === Codex config hint ===
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next: edit ~/.codex/config.toml and add:"
echo ""
echo -e "${CYAN}model_provider = \"custom\"${NC}"
echo -e "${CYAN}model = \"glm-5.1\"${NC}"
echo -e "${CYAN}model_catalog_json = \"$HOME/.codex/cc-switch-model-catalog.json\"${NC}"
echo ""
echo -e "${CYAN}[model_providers.custom]${NC}"
echo -e "${CYAN}name = \"GLM Proxy\"${NC}"
echo -e "${CYAN}base_url = \"http://127.0.0.1:18765/v4\"${NC}"
echo -e "${CYAN}wire_api = \"responses\"${NC}"
echo ""
echo "Then restart Codex Desktop."
echo "Select GLM-5.1 from model dropdown and start chatting!"
