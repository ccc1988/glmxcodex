#!/usr/bin/env bash
set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO ]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK   ]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN ]${NC} $1"; }
err()   { echo -e "${RED}[FATAL]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"    
OS="$(uname -s)"
[ "$OS" = "MINGW64_NT" ] || [ "$OS" = "MSYS_NT" ] && OS="Windows"
case "$OS" in
    Darwin)  CODEC_CONFIG="$HOME/.codex/config.toml"; CATALOG_DIR="$HOME/.codex" ;;
    Linux)   CODEC_CONFIG="$HOME/.codex/config.toml"; CATALOG_DIR="$HOME/.codex" ;;
    Windows) CODEC_CONFIG="$APPDATA/Codex/config.toml"; CATALOG_DIR="$APPDATA/Codex" ;;
    *)       CODEC_CONFIG="$HOME/.codex/config.toml"; CATALOG_DIR="$HOME/.codex" ;;
esac

CATALOG_FILE="$CATALOG_DIR/codex-glm-model-catalog.json"
CONFIG_DIR="$HOME/.config/codex-glm"
PROXY_CONFIG="$CONFIG_DIR/proxy-config.json"
PROXY_PORT="${PROXY_PORT:-18765}"
PROXY_PID="/tmp/codex-glm-proxy.pid"
PROXY_LOG="/tmp/codex-glm-proxy.log"
FIXED_ANYTHING=false

echo ""
echo -e "${CYAN} ╔══════════════════════════════════╗${NC}"
echo -e "${CYAN} ║   Codex-GLM Proxy — Fix & Repair ║${NC}"
echo -e "${CYAN} ╚══════════════════════════════════╝${NC}"
echo ""

#==================================================================
# 1. Kill cc-switch / Codex++ (they overwrite config.toml)
#==================================================================
echo -e "${YELLOW}── Check 1/5: Interference${NC}"
CCSW=$(pgrep -f "cc-switch" 2>/dev/null || true)
CCPP=$(pgrep -f "CodexPlusPlus" 2>/dev/null || true)
if [ -n "$CCSW" ] || [ -n "$CCPP" ]; then
    warn "cc-switch/Codex++ running — killing them to prevent config overwrite"
    [ -n "$CCSW" ] && kill -9 $CCSW 2>/dev/null && info "Killed cc-switch" || true
    [ -n "$CCPP" ] && kill -9 $CCPP 2>/dev/null && info "Killed Codex++" || true
    FIXED_ANYTHING=true
else
    ok "No interfering apps detected"
fi
echo ""

#==================================================================
# 2. Fix config.toml
#==================================================================
echo -e "${YELLOW}── Check 2/5: Codex config${NC}"

write_codex_config() {
    local cat p
    mkdir -p "$(dirname "$CODEC_CONFIG")"
    cat > "$CODEC_CONFIG" << TOMLEOF
model_provider = "custom"
model = "glm-5.1"
model_catalog_json = "$CATALOG_FILE"

[model_providers]
[model_providers.custom]
name = "Codex-GLM Proxy"
base_url = "http://127.0.0.1:$PROXY_PORT/v4"
wire_api = "responses"
TOML
    ok "Created: $CODEC_CONFIG"
}

if [ ! -f "$CODEC_CONFIG" ]; then
    warn "config.toml not found — creating it"
    write_codex_config
    FIXED_ANYTHING=true
else
    MODEL_LINE=$(grep "^model " "$CODEC_CONFIG" 2>/dev/null || echo "")
    BASE_URL=$(grep "^base_url " "$CODEC_CONFIG" 2>/dev/null || echo "")
    HAS_CATALOG=$(grep "model_catalog_json" "$CODEC_CONFIG" 2>/dev/null || echo "")

    NEED_FIX=false
    if ! echo "$BASE_URL" | grep -q "18765/v4"; then NEED_FIX=true; fi
    if ! echo "$MODEL_LINE" | grep -q "glm-5.1"; then NEED_FIX=true; fi
    if [ -z "$HAS_CATALOG" ]; then NEED_FIX=true; fi

    if [ "$NEED_FIX" = true ]; then
        warn "config.toml has incorrect settings — fixing"
        cp "$CODEC_CONFIG" "$(dirname "$CODEC_CONFIG")/config.toml.bak-$(date +%Y%m%d%H%M%S)"
        write_codex_config
        FIXED_ANYTHING=true
    else
        ok "config.toml is correct"
    fi
fi
echo ""

#==================================================================
# 3. Fix model catalog
#==================================================================
echo -e "${YELLOW}── Check 3/5: Model catalog${NC}"
if [ ! -f "$CATALOG_FILE" ]; then
    warn "Model catalog missing — regenerating"
    export _CF="$CATALOG_FILE"
    python3 << 'PY_CATALOG'
import json, os
cp = os.path.expanduser(os.environ.get('_CF',''))
os.makedirs(os.path.dirname(cp), exist_ok=True)
models = [
    {'id': 'glm-5.1', 'display_name': 'GLM-5.1', 'slug': 'glm-5.1', 'provider': 'zhipu',
     'visibility': 'list', 'supported_in_api': True, 'context_window': 200000, 'max_context_window': 200000,
     'description': 'GLM-5.1 (Zhipu AI)', 'input_modalities': ['text', 'image'],
     'supports_parallel_tool_calls': True, 'default_reasoning_level': 'medium',
     'supported_reasoning_levels': [{'effort': 'low'}, {'effort': 'medium'}, {'effort': 'high'}],
     'default_reasoning_summary': 'none', 'default_verbosity': 'low',
     'supports_reasoning_summaries': True, 'supports_image_detail_original': True,
     'apply_patch_tool_type': 'freeform', 'shell_type': 'shell_command', 'priority': 1000,
     'experimental_supported_tools': [], 'additional_speed_tiers': [], 'service_tiers': [],
     'model_messages': {}, 'base_instructions': 'You are Codex.', 'availability_nux': None, 'upgrade': None},
]
with open(cp, 'w') as f: json.dump({'models': models}, f, indent=2)
print('Regenerated: ' + cp)
PY_CATALOG
    FIXED_ANYTHING=true
else
    MODEL_COUNT=$(python3 -c "import json; print(len(json.load(open('$CATALOG_FILE')).get('models',[])))" 2>/dev/null || echo 0)
    [ "$MODEL_COUNT" -gt 0 ] && ok "Model catalog: $MODEL_COUNT models" || { warn "Invalid catalog"; FIXED_ANYTHING=true; }
fi
echo ""

#==================================================================
# 4. Fix proxy
#==================================================================
echo -e "${YELLOW}── Check 4/5: Proxy${NC}"
PROXY_RUNNING=false
if [ -f "$PROXY_PID" ]; then
    kill -0 "$(cat "$PROXY_PID")" 2>/dev/null && PROXY_RUNNING=true
fi
curl -s "http://localhost:$PROXY_PORT/health" >/dev/null 2>&1 && PROXY_RUNNING=true

if [ "$PROXY_RUNNING" = true ]; then
    HEALTH=$(curl -s "http://localhost:$PROXY_PORT/health" 2>/dev/null || echo "")
    ok "Proxy running — $HEALTH"
else
    warn "Proxy not running — starting it"
    lsof -ti ":$PROXY_PORT" 2>/dev/null | xargs kill -9 2>/dev/null || true
    sleep 1
    PYTHON="python3"
    command -v python3 &>/dev/null || PYTHON="python"
    nohup "$PYTHON" "$SCRIPT_DIR/proxy/proxy.py" > "$PROXY_LOG" 2>&1 &
    echo $! > "$PROXY_PID"
    sleep 3
    HEALTH=$(curl -s "http://localhost:$PROXY_PORT/health" 2>/dev/null || echo "")
    if [ -n "$HEALTH" ]; then
        ok "Proxy started — $HEALTH"
        FIXED_ANYTHING=true
    else
        warn "Proxy failed to start. Check: tail -20 $PROXY_LOG"
    fi
fi
echo ""

#==================================================================
# 5. Summary
#==================================================================
echo -e "${YELLOW}── Check 5/5: Summary${NC}"
echo ""
echo "  Proxy:  http://localhost:$PROXY_PORT/health"
echo "  Config: $CODEC_CONFIG"
echo "  Catalog: $CATALOG_FILE"
echo "  Log:    $PROXY_LOG"
echo ""

if [ "$FIXED_ANYTHING" = true ]; then
    echo -e "${YELLOW}  ⚠ Issues were fixed. Restart Codex Desktop to apply.${NC}"
else
    echo -e "${GREEN}  ✅ Everything is healthy.${NC}"
fi
echo ""
echo "  Run: open -a Codex   (or restart if already open)"
