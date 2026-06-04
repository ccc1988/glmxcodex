#!/usr/bin/env bash
set -euo pipefail

#==============================================================================
# Codex Multi-Backend Proxy — Universal Installer
# Supports: macOS, Linux (systemd), Windows (Git Bash / WSL)
#==============================================================================

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO ]${NC} $1"; }
ok()    { echo -e "${GREEN}[OK   ]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN ]${NC} $1"; }
err()   { echo -e "${RED}[FATAL]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OS="$(uname -s)"
OS_VER="$(uname -r 2>/dev/null || echo unknown)"

[ "$OS" = "MINGW64_NT" ] || [ "$OS" = "MSYS_NT" ] && OS="Windows"
case "$OS" in
    Darwin)  CODEC_CONFIG="$HOME/.codex/config.toml"; CATALOG_DIR="$HOME/.codex" ;;
    Linux)   CODEC_CONFIG="$HOME/.codex/config.toml"; CATALOG_DIR="$HOME/.codex" ;;
    Windows) CODEC_CONFIG="$APPDATA/Codex/config.toml"; CATALOG_DIR="$APPDATA/Codex" ;;
    *)       CODEC_CONFIG="$HOME/.codex/config.toml"; CATALOG_DIR="$HOME/.codex" ;;
esac

CODEC_AUTH="$CATALOG_DIR/auth.json"
CONFIG_DIR="$HOME/.config/codex-glm"
CATALOG_FILE="$CATALOG_DIR/codex-glm-model-catalog.json"
PROXY_CONFIG="$CONFIG_DIR/proxy-config.json"
PROXY_LOG="/tmp/codex-glm-proxy.log"
PROXY_PID="/tmp/codex-glm-proxy.pid"
PROXY_PORT="${PROXY_PORT:-18765}"
BACKUP_DIR="$CONFIG_DIR/backups/$(date +%Y%m%d_%H%M%S)"
DRY_RUN=false; NONINTERACTIVE=false

while [[ $# -gt 0 ]]; do case "$1" in
    --noninteractive|-y) NONINTERACTIVE=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    --port) PROXY_PORT="$2"; shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
esac; done

[ "$DRY_RUN" = true ] && info "DRY RUN — no files will be modified"

echo ""
echo -e "${CYAN} ╔══════════════════════════════════════╗${NC}"
echo -e "${CYAN} ║  Codex Multi-Backend Proxy Installer ║${NC}"
echo -e "${CYAN} ╚══════════════════════════════════════╝${NC}"
echo ""

#==================================================================
# Step 1: Environment check
#==================================================================
echo -e "${YELLOW}── Step 1/5: Environment check${NC}"
PYTHON=""
for p in python3 python; do command -v "$p" &>/dev/null && { PYTHON="$p"; break; }; done
[ -z "$PYTHON" ] && err "Python 3 required. Install: https://python.org"
PY_VER=$("$PYTHON" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
[ "$(echo "$PY_VER" | cut -d. -f1)" -lt 3 ] && err "Python >=3.8 required (found $PY_VER)"
ok "Python $PY_VER ($(which "$PYTHON"))"
command -v curl &>/dev/null && ok "curl: available" || warn "curl not found"
case "$OS" in Darwin) ok "OS: macOS $OS_VER" ;; Linux) ok "OS: Linux $OS_VER" ;; Windows) ok "OS: Windows" ;; *) warn "OS: $OS" ;; esac

# Detect cc-switch / Codex++ (they silently overwrite config.toml)
CCSW_PID=$(pgrep -f "cc-switch" 2>/dev/null || true)
CCPP_PID=$(pgrep -f "CodexPlusPlus" 2>/dev/null || true)
if [ -n "$CCSW_PID" ] || [ -n "$CCPP_PID" ]; then
    warn "cc-switch/Codex++ is running - it will overwrite config.toml!"
    warn "Close cc-switch/Codex++ before using GLM/DeepSeek with this proxy."
fi
echo ""

#==================================================================
# Step 2: Backup
#==================================================================
echo -e "${YELLOW}── Step 2/5: Backup${NC}"
backup_file() {
    local src="$1"
    [ ! -f "$src" ] && return 0
    if [ "$DRY_RUN" = true ]; then info "[DRY RUN] Would backup: $src → $BACKUP_DIR/$(basename "$src")"; return 0; fi
    mkdir -p "$BACKUP_DIR"
    cp "$src" "$BACKUP_DIR/$(basename "$src")"
    ok "Backed up: $(basename "$src")"
}
for f in "$CODEC_CONFIG" "$CODEC_AUTH" "$PROXY_CONFIG" "$CATALOG_FILE"; do backup_file "$f" 2>/dev/null || true; done
[ -d "$BACKUP_DIR" ] && ok "Backups: $BACKUP_DIR" || ok "No existing files to back up"
echo ""

#==================================================================
# Step 3: API Keys
#==================================================================
echo -e "${YELLOW}── Step 3/5: API Keys${NC}"
echo ""

load_key() {
    local varname="$1" envkey="$2" prompt="$3" val=""
    [ -n "${!envkey:-}" ] && val="${!envkey}"
    if [ -z "$val" ]; then
        export _LK_VARNAME="$varname" _LK_CDIR="$CONFIG_DIR"
        val=$(python3 << 'PY_LOAD_KEY'
import json, os, sys
vn = os.environ.get('_LK_VARNAME','')
cd = os.environ.get('_LK_CDIR','')
for d in [cd, os.path.expanduser('~/.config/codex-glm'), os.path.expanduser('~/.claude')]:
    try:
        with open(os.path.join(d,'proxy-config.json')) as f: cfg = json.load(f)
        for k in [vn,'glm','deepseek','openai']:
            kk = cfg.get('backends',{}).get(k,{}).get('api_key','')
            if kk and kk != 'PROXY_MANAGED':
                sys.stdout.write(kk); break
    except: pass
PY_LOAD_KEY
        )
        [ -n "$val" ] && info "Found existing key for $varname" >&2
    fi
    if [ -z "$val" ] && [ "$NONINTERACTIVE" = true ]; then info "$varname: skipped" >&2; echo ""; return; fi
    [ -z "$val" ] && read -rp "  $prompt: " val
    echo "$val"
}

GLM_KEY=$(load_key "glm" "GLM_API_KEY" "GLM API Key (智谱)")
DEEPSEEK_KEY=$(load_key "deepseek" "DEEPSEEK_API_KEY" "DeepSeek API Key     ")
OPENAI_KEY=$(load_key "openai" "OPENAI_API_KEY_DIRECT" "OpenAI API Key      ")

echo ""
export _GK="$GLM_KEY" _DK="$DEEPSEEK_KEY" _OK="$OPENAI_KEY" _PC="$PROXY_CONFIG" _DR="$DRY_RUN"
python3 << 'PY_WRITE_CONFIG'
import json, os
cfg = {'backends': {}}
gk = os.environ.get('_GK','').strip(); dk = os.environ.get('_DK','').strip(); ok = os.environ.get('_OK','').strip()
if gk: cfg['backends']['glm'] = {'api_key': gk, 'api_base': 'https://open.bigmodel.cn/api/coding/paas/v4'}
if dk: cfg['backends']['deepseek'] = {'api_key': dk, 'api_base': 'https://api.deepseek.com/v1'}
if ok: cfg['backends']['openai'] = {'api_key': ok, 'api_base': 'https://api.openai.com/v1'}
backends = [k for k,v in cfg['backends'].items() if v.get('api_key')]
if not backends:
    print('WARNING: No API keys configured!')
    print('Set env vars or edit: ' + os.environ.get('_PC',''))
else:
    cp = os.path.expanduser(os.environ.get('_PC',''))
    if os.environ.get('_DR','') != 'true':
        os.makedirs(os.path.dirname(cp), exist_ok=True)
        with open(cp, 'w') as f: json.dump(cfg, f, indent=2, ensure_ascii=False)
        os.chmod(cp, 0o600)
    print('Configured: ' + ', '.join(backends))
    print('Config: ' + cp)
PY_WRITE_CONFIG
[ $? -ne 0 ] && err "Failed to write config"
echo ""

#==================================================================
# Step 4: Model catalog — copy verified template
#==================================================================
echo -e "${YELLOW}── Step 4/5: Model catalog${NC}"

if [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] Would copy model catalog to $CATALOG_FILE"
else
    if [ -f "$SCRIPT_DIR/config/model-catalog.json" ]; then
        mkdir -p "$(dirname "$CATALOG_FILE")"
        cp "$SCRIPT_DIR/config/model-catalog.json" "$CATALOG_FILE"
        ok "Model catalog installed"
    elif [ -f "$CATALOG_FILE" ]; then
        ok "Model catalog already exists"
    else
        err "Model catalog template not found: $SCRIPT_DIR/config/model-catalog.json"
    fi
fi
ok "Model catalog ready"
echo ""

#==================================================================
# Step 5: Start proxy
#==================================================================
echo -e "${YELLOW}── Step 5/5: Start proxy${NC}"

if [ "$DRY_RUN" = true ]; then
    info "[DRY RUN] Would start proxy on port $PROXY_PORT"
else
    [ -f "$PROXY_PID" ] && kill "$(cat "$PROXY_PID")" 2>/dev/null && warn "Stopped old proxy" || true
    rm -f "$PROXY_PID"
    for i in 1 2 3; do
        PP=$(lsof -ti ":$PROXY_PORT" 2>/dev/null || true)
        [ -z "$PP" ] && break
        warn "Port $PROXY_PORT in use by PID $PP. Killing (attempt $i)..."
        kill -9 $PP 2>/dev/null || true
        sleep 2
    done
    STILL=$(lsof -ti ":$PROXY_PORT" 2>/dev/null || true)
    [ -n "$STILL" ] && err "Port $PROXY_PORT still in use. Manual fix: kill -9 $STILL"

    nohup "$PYTHON" "$SCRIPT_DIR/proxy/proxy.py" > "$PROXY_LOG" 2>&1 &
    PID=$!; echo "$PID" > "$PROXY_PID"; sleep 3
    kill -0 "$PID" 2>/dev/null && ok "Proxy running (PID: $PID, port: $PROXY_PORT)" || { tail -20 "$PROXY_LOG"; err "Proxy start failed."; }
fi

command -v curl &>/dev/null && [ "$DRY_RUN" = false ] && {
    H=$(curl -s "http://localhost:$PROXY_PORT/health" 2>/dev/null || true)
    [ -n "$H" ] && ok "Health: $H" || warn "Health check failed — proxy may still be starting"
}

# Auto-start
if [ "$DRY_RUN" = false ]; then
    case "$OS" in
        Darwin)
            PLIST="$HOME/Library/LaunchAgents/com.codex-glm.proxy.plist"
            mkdir -p "$HOME/Library/LaunchAgents"
            cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>com.codex-glm.proxy</string>
    <key>ProgramArguments</key><array><string>$(which "$PYTHON")</string><string>${SCRIPT_DIR}/proxy/proxy.py</string></array>
    <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
    <key>StandardOutPath</key><string>$PROXY_LOG</string>
    <key>StandardErrorPath</key><string>$PROXY_LOG</string>
</dict></plist>
PLISTEOF
            launchctl unload "$PLIST" 2>/dev/null || true
            launchctl load "$PLIST" 2>/dev/null && ok "LaunchAgent: auto-start enabled" || true
            ;;
        Linux)
            command -v systemctl &>/dev/null && {
                SF="$HOME/.config/systemd/user/codex-glm-proxy.service"; mkdir -p "$(dirname "$SF")"
                cat > "$SF" << SERVICEEOF
[Unit]
Description=Codex Multi-Backend Proxy
After=network.target
[Service]
ExecStart=$(which "$PYTHON") ${SCRIPT_DIR}/proxy/proxy.py
Restart=always; RestartSec=5
[Install]
WantedBy=default.target
SERVICEEOF
                systemctl --user daemon-reload 2>/dev/null || true
                systemctl --user enable codex-glm-proxy.service 2>/dev/null || true
                systemctl --user start codex-glm-proxy.service 2>/dev/null && ok "systemd: auto-start enabled" || warn "systemd failed"
            } || warn "systemd not found"
            ;;
        Windows) info "Windows: use proxy/start.bat or Task Scheduler" ;;
    esac
fi

#==================================================================
# Auto-configure Codex config.toml
#==================================================================
echo ""
echo -e "${GREEN} ╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN} ║       Installation Complete!         ║${NC}"
echo -e "${GREEN} ╚══════════════════════════════════════╝${NC}"
echo ""

# Kill any cc-switch/Codex++ that would overwrite our config
CCSW=$(pgrep -f "cc-switch" 2>/dev/null || true)
CCPP=$(pgrep -f "CodexPlusPlus" 2>/dev/null || true)
[ -n "$CCSW" ] && kill -9 $CCSW 2>/dev/null && warn "Killed cc-switch to prevent config overwrite" || true
[ -n "$CCPP" ] && kill -9 $CCPP 2>/dev/null && warn "Killed Codex++ to prevent config overwrite" || true

# Write/update config.toml
mkdir -p "$(dirname "$CODEC_CONFIG")"
if [ -f "$CODEC_CONFIG" ]; then
    # Update existing config — only change model + base_url lines
    TMP_CONFIG="${CODEC_CONFIG}.tmp-$$"
    cp "$CODEC_CONFIG" "$TMP_CONFIG"
    if grep -q "^model " "$TMP_CONFIG" 2>/dev/null; then
        sed -i '' "s/^model = .*/model = \"glm-5.1\"/" "$TMP_CONFIG" 2>/dev/null || sed -i "s/^model = .*/model = \"glm-5.1\"/" "$TMP_CONFIG" 2>/dev/null
    else
        echo "model = \"glm-5.1\"" >> "$TMP_CONFIG"
    fi
    if grep -q "model_catalog_json" "$TMP_CONFIG" 2>/dev/null; then
        sed -i '' "s|model_catalog_json = .*|model_catalog_json = \"$CATALOG_FILE\"|" "$TMP_CONFIG" 2>/dev/null || sed -i "s|model_catalog_json = .*|model_catalog_json = \"$CATALOG_FILE\"|" "$TMP_CONFIG" 2>/dev/null
    else
        TMP2="${TMP_CONFIG}.2"
        awk -v line="model_catalog_json = \"$CATALOG_FILE\"" '/^model =/{print; print line; next}1' "$TMP_CONFIG" > "$TMP2" && mv "$TMP2" "$TMP_CONFIG"
    fi
    if grep -q "^base_url " "$TMP_CONFIG" 2>/dev/null; then
        sed -i '' "s|^base_url = .*|base_url = \"http://127.0.0.1:$PROXY_PORT/v4\"|" "$TMP_CONFIG" 2>/dev/null || sed -i "s|^base_url = .*|base_url = \"http://127.0.0.1:$PROXY_PORT/v4\"|" "$TMP_CONFIG" 2>/dev/null
    fi
    if ! grep -q "^wire_api " "$TMP_CONFIG" 2>/dev/null; then
        TMP2="${TMP_CONFIG}.2"
        awk -v line='wire_api = "responses"' '/^base_url =/{print; print line; next}1' "$TMP_CONFIG" > "$TMP2" && mv "$TMP2" "$TMP_CONFIG"
    fi
    if grep -q "^requires_openai_auth " "$TMP_CONFIG" 2>/dev/null; then
        sed -i '' "s/^requires_openai_auth = .*/requires_openai_auth = true/" "$TMP_CONFIG" 2>/dev/null || sed -i "s/^requires_openai_auth = .*/requires_openai_auth = true/" "$TMP_CONFIG" 2>/dev/null
    else
        TMP2="${TMP_CONFIG}.2"
        awk -v line='requires_openai_auth = true' '/^wire_api =/{print; print line; next}1' "$TMP_CONFIG" > "$TMP2" && mv "$TMP2" "$TMP_CONFIG"
    fi
    mv "$TMP_CONFIG" "$CODEC_CONFIG"
    ok "Updated: $CODEC_CONFIG"
else
    cat > "$CODEC_CONFIG" << TOMLEOF
model_provider = "custom"
model = "glm-5.1"
model_catalog_json = "$CATALOG_FILE"

[model_providers]
[model_providers.custom]
name = "Codex-GLM Proxy"
base_url = "http://127.0.0.1:$PROXY_PORT/v4"
wire_api = "responses"
TOMLEOF
    ok "Created: $CODEC_CONFIG"
fi

echo ""
echo "  Proxy:   http://localhost:$PROXY_PORT/health"
echo "  Config:  $PROXY_CONFIG"
echo "  Catalog: $CATALOG_FILE"
echo "  Backup:  $BACKUP_DIR"
echo ""
echo -e "  ${GREEN}Restart Codex Desktop and select GLM-5.1.${NC}"
echo ""
echo "  If anything breaks later, run: ${CYAN}./proxy/fix.sh${NC}"
[ "$DRY_RUN" = true ] && echo -e "${YELLOW}DRY RUN — run without --dry-run to apply${NC}"
echo "  Then restart Codex Desktop and select GLM-5.1."
[ "$DRY_RUN" = true ] && echo -e "${YELLOW}DRY RUN — run without --dry-run to apply${NC}"
