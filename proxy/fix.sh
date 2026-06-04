#!/usr/bin/env bash
set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO ]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK   ]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN ]${NC} $1"; }

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
# 1. Kill cc-switch / Codex++
#==================================================================
echo -e "${YELLOW}── Check 1/5: Interference${NC}"
CCSW=$(pgrep -f "cc-switch" 2>/dev/null || true)
CCPP=$(pgrep -f "CodexPlusPlus" 2>/dev/null || true)
if [ -n "$CCSW" ] || [ -n "$CCPP" ]; then
    warn "cc-switch/Codex++ running — killing to prevent config overwrite"
    [ -n "$CCSW" ] && kill -9 $CCSW 2>/dev/null || true
    [ -n "$CCPP" ] && kill -9 $CCPP 2>/dev/null || true
    FIXED_ANYTHING=true
else
    ok "No interfering apps detected"
fi
echo ""

#==================================================================
# 2. Fix config.toml
#==================================================================
echo -e "${YELLOW}── Check 2/5: Codex config${NC}"
NEED_FIX=false
if [ ! -f "$CODEC_CONFIG" ]; then
    NEED_FIX=true
else
    if ! grep -q "18765/v4" "$CODEC_CONFIG" 2>/dev/null; then NEED_FIX=true; fi
    if ! grep -q 'model = "glm-5.1"' "$CODEC_CONFIG" 2>/dev/null; then NEED_FIX=true; fi
    if ! grep -q "model_catalog_json" "$CODEC_CONFIG" 2>/dev/null; then NEED_FIX=true; fi
fi

if [ "$NEED_FIX" = true ]; then
    warn "config.toml needs fixing"
    if [ -f "$CODEC_CONFIG" ]; then
        cp "$CODEC_CONFIG" "$CODEC_CONFIG.bak-$(date +%Y%m%d%H%M%S)"
    fi
    mkdir -p "$(dirname "$CODEC_CONFIG")"
    printf 'model_provider = "custom"\nmodel = "glm-5.1"\nmodel_catalog_json = "%s"\n\n[model_providers]\n[model_providers.custom]\nname = "Codex-GLM Proxy"\nwire_api = "responses"\nrequires_openai_auth = true\nbase_url = "http://127.0.0.1:%s/v4"\n' "$CATALOG_FILE" "$PROXY_PORT" > "$CODEC_CONFIG"
    ok "Fixed: $CODEC_CONFIG"
    FIXED_ANYTHING=true
else
    ok "config.toml is correct"
fi
echo ""

#==================================================================
# 3. Fix model catalog
#==================================================================
echo -e "${YELLOW}── Check 3/5: Model catalog${NC}"
if [ ! -f "$CATALOG_FILE" ]; then
    warn "Model catalog missing — regenerating"
    mkdir -p "$(dirname "$CATALOG_FILE")"
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
with open(cp, 'w') as f:
    json.dump({'models': models}, f, indent=2)
print('Regenerated: ' + cp)
PY_CATALOG
    FIXED_ANYTHING=true
else
    N=$(python3 -c "import json;print(len(json.load(open('$CATALOG_FILE')).get('models',[])))" 2>/dev/null || echo 0)
    [ "$N" -gt 0 ] && ok "Model catalog: $N models" || { warn "Invalid catalog"; FIXED_ANYTHING=true; }
fi
echo ""

#==================================================================
# 4. Fix proxy
#==================================================================
echo -e "${YELLOW}── Check 4/5: Proxy${NC}"
PROXY_RUNNING=false
if [ -f "$PROXY_PID" ] && kill -0 "$(cat "$PROXY_PID")" 2>/dev/null; then
    PROXY_RUNNING=true
fi
curl -s "http://localhost:$PROXY_PORT/health" >/dev/null 2>&1 && PROXY_RUNNING=true

if [ "$PROXY_RUNNING" = true ]; then
    H=$(curl -s "http://localhost:$PROXY_PORT/health" 2>/dev/null || echo "")
    ok "Proxy running — $H"
else
    warn "Proxy not running — starting"
    lsof -ti ":$PROXY_PORT" 2>/dev/null | xargs kill -9 2>/dev/null || true
    sleep 1
    PYTHON=""; for p in python3 python; do command -v "$p" &>/dev/null && { PYTHON="$p"; break; }; done
    PYTHON="${PYTHON:-python3}"
    nohup "$PYTHON" "$SCRIPT_DIR/proxy.py" > "$PROXY_LOG" 2>&1 &
    echo $! > "$PROXY_PID"
    sleep 3
    H=$(curl -s "http://localhost:$PROXY_PORT/health" 2>/dev/null || echo "")
    if [ -n "$H" ]; then
        ok "Proxy started — $H"
        FIXED_ANYTHING=true
    else
        warn "Proxy start failed. Log: tail -20 $PROXY_LOG"
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
    echo "  Restart Codex Desktop to apply fixes."
else
    echo "  All good."
fi
echo ""
