#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# Codex Multi-Backend Proxy — Universal Installer
# Supports: macOS (≥10.15), Linux (systemd), Windows (Git Bash / WSL)
#==============================================================================

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO ]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK   ]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN ]${NC} $1"; }
err()   { echo -e "${RED}[FATAL]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"
OS_VER="$(uname -r 2>/dev/null || echo unknown)"

# --- Config paths (cross-platform) ---
if [ "$OS" = "MINGW64_NT" ] || [ "$OS" = "MSYS_NT" ]; then
    OS="Windows"
fi
case "$OS" in
    Darwin)
        CODEC_CONFIG="$HOME/.codex/config.toml"
        CODEC_AUTH="$HOME/.codex/auth.json"
        CATALOG_DIR="$HOME/.codex"
        ;;
    Linux)
        CODEC_CONFIG="$HOME/.codex/config.toml"
        CODEC_AUTH="$HOME/.codex/auth.json"
        CATALOG_DIR="$HOME/.codex"
        ;;
    Windows)
        CODEC_CONFIG="$APPDATA/Codex/config.toml"
        CODEC_AUTH="$APPDATA/Codex/auth.json"
        CATALOG_DIR="$APPDATA/Codex"
        ;;
    *)
        CODEC_CONFIG="$HOME/.codex/config.toml"
        CODEC_AUTH="$HOME/.codex/auth.json"
        CATALOG_DIR="$HOME/.codex"
        ;;
esac

CONFIG_DIR="$HOME/.config/codex-glm"
CATALOG_FILE="$CATALOG_DIR/codex-glm-model-catalog.json"
PROXY_CONFIG="$CONFIG_DIR/proxy-config.json"
PROXY_LOG="/tmp/codex-glm-proxy.log"
PROXY_PID="/tmp/codex-glm-proxy.pid"
PROXY_PORT="${PROXY_PORT:-18765}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$CONFIG_DIR/backups/$TIMESTAMP"
DRY_RUN=false
NONINTERACTIVE=false

#==================================================================
# Parse flags
#==================================================================
while [[ $# -gt 0 ]]; do case "$1" in
    --noninteractive|-y) NONINTERACTIVE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --port) PROXY_PORT="$2"; shift 2 ;;
    *) echo "Unknown: $1"; echo "Usage: ./install.sh [--noninteractive] [--dry-run] [--port NNNN]"; exit 1 ;;
esac; done

if [ "$DRY_RUN" = true ]; then
    info "DRY RUN — no files will be modified"
fi

#==================================================================
# Banner
#==================================================================
echo ""
echo -e "${CYAN} ╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN} ║  Codex Multi-Backend Proxy Installer ║${NC}"
echo -e "${CYAN} ╚══════════════════════════════════════╝${NC}"
echo ""

#==================================================================
# Section 1: Environment pre-checks
#==================================================================
echo -e "${YELLOW}── Step 1/5: Environment check${NC}"

PYTHON=""
for p in python3 python; do
    if command -v "$p" &>/dev/null; then
        PYTHON="$p"
        break
    fi
done
[ -z "$PYTHON" ] && err "Python 3 is required. Install from https://python.org"
PY_VER=$("$PYTHON" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
PY_MAJOR=$(echo "$PY_VER" | cut -d. -f1)
[ "$PY_MAJOR" -lt 3 ] && err "Python ≥3.8 required (found Python $PY_VER)"
ok "Python $PY_VER ($(which "$PYTHON"))"

if command -v curl &>/dev/null; then
    ok "curl: available"
else
    warn "curl not found — health check will be skipped"
fi

case "$OS" in
    Darwin) ok "OS: macOS $OS_VER" ;;
    Linux)  ok "OS: Linux $OS_VER" ;;
    Windows) ok "OS: Windows" ;;
    *)      warn "Unrecognized OS: $OS. Proceeding anyway." ;;
esac

echo ""

#==================================================================
# Section 2: Backup existing configuration
#==================================================================
echo -e "${YELLOW}── Step 2/5: Backup${NC}"

backup_file() {
    local src="$1"
    if [ ! -f "$src" ]; then return 0; fi
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would backup: $src → $BACKUP_DIR/$(basename "$src")"
        return 0
    fi
    mkdir -p "$BACKUP_DIR"
    cp "$src" "$BACKUP_DIR/$(basename "$src")"
    ok "Backed up: $(basename "$src")"
}

backup_file "$CODEC_CONFIG" 2>/dev/null || true
backup_file "$CODEC_AUTH" 2>/dev/null || true
backup_file "$PROXY_CONFIG" 2>/dev/null || true
backup_file "$CATALOG_FILE" 2>/dev/null || true

if [ -d "$BACKUP_DIR" ]; then
    ok "Backups saved to: $BACKUP_DIR"
elif [ "$DRY_RUN" = false ]; then
    ok "No existing files to back up"
fi
echo ""

#==================================================================
# Section 3: API Key configuration
#==================================================================
echo -e "${YELLOW}── Step 3/5: API Keys${NC}"
echo ""

load_key() {
    local varname="$1" envkey="$2" prompt="$3"
    local val=""

    [ -n "${!envkey:-}" ] && val="${!envkey}"

    if [ -z "$val" ]; then
        val="$(python3 -c "
import json, os
for d in ['$CONFIG_DIR', os.path.expanduser('~/.config/codex-glm'), os.path.expanduser('~/.claude')]:
    try:
        with open(os.path.join(d, 'proxy-config.json')) as f:
            cfg = json.load(f)
        for k in ['$varname', 'glm', 'deepseek', 'openai']:
            if k in cfg.get('backends',{}):
                kk = cfg['backends'][k].get('api_key','')
                if kk and kk != 'PROXY_MANAGED':
                    print(kk)
                    break
    except: pass
" 2>/dev/null)"
        if [ -n "$val" ]; then
            info "Found existing key for $varname" >&2
        fi
    fi

    if [ -z "$val" ] && [ "$NONINTERACTIVE" = true ]; then
        info "$varname: skipped (empty, non-interactive mode)" >&2
        echo ""
        return
    fi

    if [ -z "$val" ]; then
        read -rp "  $prompt: " val
    fi

    echo "$val"
}

GLM_KEY=$(load_key "glm" "GLM_API_KEY" "GLM API Key (智谱)")
DEEPSEEK_KEY=$(load_key "deepseek" "DEEPSEEK_API_KEY" "DeepSeek API Key     ")
OPENAI_KEY=$(load_key "openai" "OPENAI_API_KEY_DIRECT" "OpenAI API Key      ")

KEYS_CONFIGURED=0
[ -n "$GLM_KEY" ] && KEYS_CONFIGURED=1

echo ""
python3 -c "
import json, os
cfg_path = os.path.expanduser('$PROXY_CONFIG')
cfg = {'backends': {}}
if '$GLM_KEY':
    cfg['backends']['glm'] = {'api_key': '$GLM_KEY', 'api_base': 'https://open.bigmodel.cn/api/coding/paas/v4'}
if '$DEEPSEEK_KEY':
    cfg['backends']['deepseek'] = {'api_key': '$DEEPSEEK_KEY', 'api_base': 'https://api.deepseek.com/v1'}
if '$OPENAI_KEY':
    cfg['backends']['openai'] = {'api_key': '$OPENAI_KEY', 'api_base': 'https://api.openai.com/v1'}
backends = [k for k,v in cfg['backends'].items() if v.get('api_key')]
if not backends:
    print('WARNING: No API keys configured!')
    print('Set env vars or edit: ' + cfg_path)
else:
    if '$DRY_RUN' == 'false':
        os.makedirs(os.path.dirname(cfg_path), exist_ok=True)
        with open(cfg_path, 'w') as f:
            json.dump(cfg, f, indent=2, ensure_ascii=False)
        os.chmod(cfg_path, 0o600)
    print('Configured: ' + ', '.join(backends))
    print('Config: ' + cfg_path)
" || err "Failed to write config"
echo ""

#==================================================================
# Section 4: Model catalog
#==================================================================
echo -e "${YELLOW}── Step 4/5: Model catalog${NC}"

python3 -c "
import json, os

models = [
    {
        'id': 'glm-5.1', 'display_name': 'GLM-5.1', 'slug': 'glm-5.1',
        'provider': 'zhipu', 'visibility': 'list', 'supported_in_api': True,
        'context_window': 200000, 'max_context_window': 200000,
        'description': 'GLM-5.1 (智谱 AI)',
        'input_modalities': ['text', 'image'],
        'supports_parallel_tool_calls': True,
        'default_reasoning_level': 'medium',
        'supported_reasoning_levels': [
            {'effort': 'low', 'description': 'Fast'},
            {'effort': 'medium', 'description': 'Balanced'},
            {'effort': 'high', 'description': 'Deep'}
        ],
        'default_reasoning_summary': 'none', 'default_verbosity': 'low',
        'support_verbosity': True, 'supports_reasoning_summaries': True,
        'supports_image_detail_original': True,
        'supports_search_tool': False, 'web_search_tool_type': 'text_and_image',
        'effective_context_window_percent': 95,
        'truncation_policy': {'mode': 'tokens', 'limit': 10000},
        'apply_patch_tool_type': 'freeform', 'shell_type': 'shell_command',
        'experimental_supported_tools': [], 'additional_speed_tiers': [],
        'service_tiers': [], 'priority': 1000,
        'model_messages': {'instructions_template': 'You are Codex, a coding agent.'},
        'base_instructions': 'You are Codex, a coding agent powered by GLM (智谱 AI).',
        'availability_nux': None, 'upgrade': None,
    },
    {
        'id': 'glm-5', 'display_name': 'GLM-5', 'slug': 'glm-5',
        'provider': 'zhipu', 'visibility': 'list', 'supported_in_api': True,
        'context_window': 128000, 'max_context_window': 128000,
        'description': 'GLM-5 (智谱 AI)',
        'input_modalities': ['text'],
        'supports_parallel_tool_calls': True,
        'default_reasoning_level': 'medium',
        'supported_reasoning_levels': [
            {'effort': 'low', 'description': 'Fast'},
            {'effort': 'medium', 'description': 'Balanced'}
        ],
        'default_reasoning_summary': 'none', 'default_verbosity': 'low',
        'support_verbosity': True, 'supports_reasoning_summaries': True,
        'supports_image_detail_original': False,
        'supports_search_tool': False, 'web_search_tool_type': 'text_and_image',
        'effective_context_window_percent': 95,
        'truncation_policy': {'mode': 'tokens', 'limit': 10000},
        'apply_patch_tool_type': 'freeform', 'shell_type': 'shell_command',
        'experimental_supported_tools': [], 'additional_speed_tiers': [],
        'service_tiers': [], 'priority': 900,
        'model_messages': {'instructions_template': 'You are Codex, a coding agent.'},
        'base_instructions': 'You are Codex, a coding agent powered by GLM (智谱 AI).',
        'availability_nux': None, 'upgrade': None,
    },
]

if '$DEEPSEEK_KEY':
    models.append({
        'id': 'deepseek-chat', 'display_name': 'DeepSeek Chat', 'slug': 'deepseek-chat',
        'provider': 'deepseek', 'visibility': 'list', 'supported_in_api': True,
        'context_window': 128000, 'max_context_window': 128000,
        'description': 'DeepSeek Chat',
        'input_modalities': ['text'],
        'supports_parallel_tool_calls': True,
        'default_reasoning_level': 'medium',
        'supported_reasoning_levels': [{'effort': 'medium'}],
        'default_reasoning_summary': 'none', 'default_verbosity': 'low',
        'support_verbosity': True, 'supports_reasoning_summaries': True,
        'supports_image_detail_original': False,
        'supports_search_tool': False, 'web_search_tool_type': 'text_and_image',
        'effective_context_window_percent': 95,
        'truncation_policy': {'mode': 'tokens', 'limit': 10000},
        'apply_patch_tool_type': 'freeform', 'shell_type': 'shell_command',
        'experimental_supported_tools': [], 'additional_speed_tiers': [],
        'service_tiers': [], 'priority': 800,
        'model_messages': {'instructions_template': 'You are Codex, a coding agent.'},
        'base_instructions': 'You are Codex, a coding agent powered by DeepSeek.',
        'availability_nux': None, 'upgrade': None,
    })

catalog_path = os.path.expanduser('$CATALOG_FILE')
data = {'models': models}
if '$DRY_RUN' == 'false':
    os.makedirs(os.path.dirname(catalog_path), exist_ok=True)
    with open(catalog_path, 'w') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
print(f'Model catalog: {catalog_path} ({len(models)} models)')
" || err "Failed to generate model catalog"

ok "Model catalog ready"
echo ""

#==================================================================
# Section 5: Start proxy + auto-start
#==================================================================
echo -e "${YELLOW}── Step 5/5: Start proxy${NC}"

if [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] Would start proxy on port $PROXY_PORT"
else
    # Stop old proxy by PID file
    if [ -f "$PROXY_PID" ]; then
        OLD_PID=$(cat "$PROXY_PID")
        kill "$OLD_PID" 2>/dev/null && warn "Stopped old proxy (PID: $OLD_PID)" || true
        rm -f "$PROXY_PID"
    fi

    # Aggressively free the port - try up to 3 times
    PORT_ATTEMPTS=0
    while command -v lsof &>/dev/null && [ $PORT_ATTEMPTS -lt 3 ]; do
        PORT_PID=$(lsof -ti ":$PROXY_PORT" 2>/dev/null || true)
        [ -z "$PORT_PID" ] && break
        warn "Port $PROXY_PORT in use by PID $PORT_PID. Killing..."
        kill -9 $PORT_PID 2>/dev/null || true
        sleep 2
        PORT_ATTEMPTS=$((PORT_ATTEMPTS + 1))
    done

    # Final check
    if command -v lsof &>/dev/null; then
        STILL=$(lsof -ti ":$PROXY_PORT" 2>/dev/null || true)
        if [ -n "$STILL" ]; then
            err "Port $PROXY_PORT still in use after cleanup. Manual fix: kill -9 $STILL"
        fi
    fi

    # Start fresh
    nohup "$PYTHON" "$SCRIPT_DIR/proxy/proxy.py" > "$PROXY_LOG" 2>&1 &
    PID=$!
    echo "$PID" > "$PROXY_PID"
    sleep 3

    if kill -0 "$PID" 2>/dev/null; then
        ok "Proxy running (PID: $PID, port: $PROXY_PORT)"
    else
        warn "Proxy may have failed to start. Check log:"
        tail -20 "$PROXY_LOG"
        err "Proxy start failed. Review log above."
    fi
fi

# Health check
if command -v curl &>/dev/null && [ "$DRY_RUN" = false ]; then
    HEALTH=$(curl -s "http://localhost:$PROXY_PORT/health" 2>/dev/null || echo "")
    if [ -n "$HEALTH" ]; then
        ok "Health check: $HEALTH"
    else
        warn "Health check failed. Proxy may not be ready yet."
    fi
fi

# Auto-start setup (platform-specific)
if [ "$DRY_RUN" = false ]; then
    case "$OS" in
        Darwin)
            PLIST="$HOME/Library/LaunchAgents/com.codex-glm.proxy.plist"
            mkdir -p "$HOME/Library/LaunchAgents"
            cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.codex-glm.proxy</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which "$PYTHON")</string>
        <string>${SCRIPT_DIR}/proxy/proxy.py</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$PROXY_LOG</string>
    <key>StandardErrorPath</key><string>$PROXY_LOG</string>
</dict>
</plist>
PLISTEOF
            launchctl unload "$PLIST" 2>/dev/null || true
            launchctl load "$PLIST" 2>/dev/null && ok "LaunchAgent: auto-start enabled"
            ;;
        Linux)
            if command -v systemctl &>/dev/null; then
                SERVICE_FILE="$HOME/.config/systemd/user/codex-glm-proxy.service"
                mkdir -p "$(dirname "$SERVICE_FILE")"
                cat > "$SERVICE_FILE" << SERVICEEOF
[Unit]
Description=Codex Multi-Backend Proxy
After=network.target

[Service]
ExecStart=$(which "$PYTHON") ${SCRIPT_DIR}/proxy/proxy.py
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
SERVICEEOF
                systemctl --user daemon-reload 2>/dev/null || true
                systemctl --user enable codex-glm-proxy.service 2>/dev/null || true
                systemctl --user start codex-glm-proxy.service 2>/dev/null && ok "systemd: auto-start enabled" || warn "systemd start failed — check: systemctl --user status codex-glm-proxy"
            else
                warn "systemd not found. Auto-start not configured."
            fi
            ;;
        Windows)
            info "Windows: start manually with proxy/start.bat"
            info "To auto-start, add to Task Scheduler or startup folder."
            ;;
    esac
fi

echo ""

#==================================================================
# Final summary
#==================================================================
echo -e "${GREEN} ╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN} ║       Installation Complete! 🎉       ║${NC}"
echo -e "${GREEN} ╚══════════════════════════════════════╝${NC}"
echo ""
echo "  Proxy:     http://localhost:$PROXY_PORT"
echo "  Health:    http://localhost:$PROXY_PORT/health"
echo "  Log:       $PROXY_LOG"
echo "  Config:    $PROXY_CONFIG"
echo "  Catalog:   $CATALOG_FILE"
if [ -d "$BACKUP_DIR" ]; then
    echo "  Backups:   $BACKUP_DIR"
fi
echo ""

if [ ! -f "$CODEC_CONFIG" ]; then
    echo -e "${YELLOW}  ┌─────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}  │ ACTION REQUIRED: Configure Codex Desktop    │${NC}"
    echo -e "${YELLOW}  └─────────────────────────────────────────────┘${NC}"
    echo ""
    echo "  Create ${CODEC_CONFIG}:"
    echo ""
    echo -e "    ${CYAN}model_provider = \"custom\"${NC}"
    echo -e "    ${CYAN}model = \"glm-5.1\"${NC}"
    echo -e "    ${CYAN}model_catalog_json = \"${CATALOG_FILE}\"${NC}"
    echo ""
    echo -e "    ${CYAN}[model_providers.custom]${NC}"
    echo -e "    ${CYAN}name = \"Codex-GLM Proxy\"${NC}"
    echo -e "    ${CYAN}base_url = \"http://127.0.0.1:${PROXY_PORT}/v4\"${NC}"
    echo -e "    ${CYAN}wire_api = \"responses\"${NC}"
    echo ""
else
    echo -e "${YELLOW}  ┌─────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}  │ ACTION REQUIRED: Update Codex config        │${NC}"
    echo -e "${YELLOW}  └─────────────────────────────────────────────┘${NC}"
    echo ""
    echo "  Your existing ${CODEC_CONFIG} has been backed up."
    echo "  Edit it to add/update these lines:"
    echo ""
    echo -e "    ${CYAN}model = \"glm-5.1\"${NC}"
    echo -e "    ${CYAN}model_catalog_json = \"${CATALOG_FILE}\"${NC}"
    echo ""
    echo -e "    ${CYAN}[model_providers.custom]${NC}"
    echo -e "    ${CYAN}base_url = \"http://127.0.0.1:${PROXY_PORT}/v4\"${NC}"
    echo -e "    ${CYAN}wire_api = \"responses\"${NC}"
    echo ""
fi

echo "  Then restart Codex Desktop."
echo -e "  Select ${CYAN}GLM-5.1${NC} from the model dropdown."
echo ""

if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}This was a dry run. Run without --dry-run to apply.${NC}"
fi
