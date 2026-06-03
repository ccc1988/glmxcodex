#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LITELLM_CONFIG_DIR="$HOME/.claude"
CODEX_CONFIG_DIR="$HOME/.codex"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LITELLM_PORT=4000
PLIST_NAME="com.litellm.proxy"
PYTHON_BIN=""
LITELLM_BIN=""
BACKUP_DIR=""

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
fatal()   { echo -e "${RED}[FATAL]${NC} $1"; exit 1; }

banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}        Codex + 智谱 GLM 一键安装配置工具        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   Codex Desktop → litellm → 智谱 GLM (GLM-5.1)  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

backup_existing() {
    local has_existing=false
    for f in "$LITELLM_CONFIG_DIR/litellm-config.yaml" "$CODEX_CONFIG_DIR/config.toml" "$CODEX_CONFIG_DIR/auth.json"; do
        if [[ -f "$f" ]]; then
            has_existing=true
            break
        fi
    done

    if [[ "$has_existing" != "true" ]]; then
        return
    fi

    BACKUP_DIR="$HOME/.codex-glm-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    info "检测到已有配置，备份到 $BACKUP_DIR"

    for f in "$LITELLM_CONFIG_DIR/litellm-config.yaml" "$CODEX_CONFIG_DIR/config.toml" "$CODEX_CONFIG_DIR/auth.json"; do
        if [[ -f "$f" ]]; then
            cp "$f" "$BACKUP_DIR/"
            info "备份: $(basename $f)"
        fi
    done
}

preflight_check() {
    info "====== 预检 ======"

    if [[ "$(uname)" != "Darwin" ]]; then
        fatal "本工具目前仅支持 macOS 系统"
    fi
    success "操作系统: macOS"

    if [[ -d "/Applications/Codex.app" ]]; then
        success "Codex Desktop: 已安装"
    else
        warn "未检测到 /Applications/Codex.app，Codex Desktop 是否已安装？"
        read -p "继续安装? [y/N]: " cont
        [[ "$cont" =~ ^[Yy] ]] || exit 0
    fi

    if ! command -v curl &>/dev/null; then
        fatal "curl 未安装"
    fi
    if ! command -v lsof &>/dev/null; then
        fatal "lsof 未安装"
    fi
    success "基础工具: curl, lsof 可用"
}

find_python() {
    info "====== 检测 Python 环境 ======"

    local candidates=(
        "/opt/miniconda3/bin/python3"
        "$HOME/miniconda3/bin/python3"
        "$HOME/miniforge3/bin/python3"
        "/opt/miniforge3/bin/python3"
        "/opt/homebrew/bin/python3"
        "/usr/local/bin/python3"
    )

    for p in "${candidates[@]}"; do
        if [[ -x "$p" ]]; then
            local ver=$($p -c "import sys; v=sys.version_info; print(f'{v.major}.{v.minor}')")
            local major=$(echo "$ver" | cut -d. -f1)
            local minor=$(echo "$ver" | cut -d. -f2)
            if [[ "$major" -eq 3 && "$minor" -ge 10 && "$minor" -le 13 ]]; then
                PYTHON_BIN="$p"
                success "Python $ver ($PYTHON_BIN)"
                export PYTHON_BIN
                return
            else
                warn "跳过 $p (版本 $ver，需要 3.10~3.13)"
            fi
        fi
    done

    if command -v python3 &>/dev/null; then
        local p=$(command -v python3)
        local ver=$($p -c "import sys; v=sys.version_info; print(f'{v.major}.{v.minor}')")
        local minor=$(echo "$ver" | cut -d. -f2)
        if [[ "$minor" -ge 10 && "$minor" -le 13 ]]; then
            PYTHON_BIN="$p"
            success "Python $ver ($PYTHON_BIN)"
            export PYTHON_BIN
            return
        fi
        if [[ "$minor" -gt 13 ]]; then
            fatal "系统 Python 版本为 $ver，litellm 依赖的 orjson 不支持 Python 3.14+。\n请安装 Python 3.10~3.13 (推荐 Miniconda: https://docs.conda.io/en/latest/miniconda.html)"
        fi
    fi

    fatal "未找到 Python 3.10~3.13，请安装 (推荐 Miniconda: https://docs.conda.io/en/latest/miniconda.html)"
}

install_litellm() {
    info "====== 安装 litellm ======"

    if ! $PYTHON_BIN -m pip --version &>/dev/null; then
        fatal "pip 不可用"
    fi

    if $PYTHON_BIN -c "import litellm" 2>/dev/null; then
        local ver=$($PYTHON_BIN -c "import importlib.metadata; print(importlib.metadata.version('litellm'))")
        success "litellm 已安装，版本: $ver"

        local need_upgrade=false
        if ! $PYTHON_BIN -c "import packaging.version; exit(0 if packaging.version.Version('$ver') >= packaging.version.Version('1.66.3') else 1)" 2>/dev/null; then
            need_upgrade=true
        fi

        try_import_proxy=$($PYTHON_BIN -c "from litellm.proxy.proxy_server import *" 2>&1)
        if [[ $? -ne 0 ]]; then
            need_upgrade=true
        fi

        if [[ "$need_upgrade" == "true" ]]; then
            info "正在升级 litellm[proxy] ..."
            $PYTHON_BIN -m pip install --upgrade 'litellm[proxy]' || fatal "litellm 升级失败"
            success "litellm 升级完成"
        fi
    else
        info "正在安装 litellm[proxy] ..."
        $PYTHON_BIN -m pip install 'litellm[proxy]' || fatal "litellm 安装失败"
        success "litellm 安装完成"
    fi

    LITELLM_BIN=$($PYTHON_BIN -c "import shutil; print(shutil.which('litellm'))" 2>/dev/null)
    if [[ -z "$LITELLM_BIN" || ! -x "$LITELLM_BIN" ]]; then
        LITELLM_BIN="$(dirname $PYTHON_BIN)/litellm"
    fi
    if [[ ! -x "$LITELLM_BIN" ]]; then
        fatal "找不到 litellm 可执行文件"
    fi
    success "litellm 可执行文件: $LITELLM_BIN"
}

ask_config() {
    echo ""
    info "====== 配置信息 ======"
    echo ""

    if [[ -f "$LITELLM_CONFIG_DIR/litellm-config.yaml" ]]; then
        local old_key=$(grep "api_key:" "$LITELLM_CONFIG_DIR/litellm-config.yaml" 2>/dev/null | head -1 | sed 's/.*api_key: *//')
        local old_base=$(grep "api_base:" "$LITELLM_CONFIG_DIR/litellm-config.yaml" 2>/dev/null | head -1 | sed 's/.*api_base: *//')
        local old_model=$(grep "model_name:" "$LITELLM_CONFIG_DIR/litellm-config.yaml" 2>/dev/null | head -1 | sed 's/.*model_name: *//')

        if [[ -n "$old_key" && "$old_key" != "YOUR_API_KEY_HERE" ]]; then
            echo -e "${YELLOW}检测到已有配置:${NC}"
            echo "  API Key: ${old_key:0:8}..."
            echo "  接口: $old_base"
            echo "  模型: $old_model"
            echo ""
            read -p "是否沿用已有配置? [Y/n]: " reuse
            reuse=${reuse:-Y}
            if [[ "$reuse" =~ ^[Yy] ]]; then
                API_KEY="$old_key"
                API_BASE="$old_base"
                MODEL="$old_model"
                success "沿用已有配置"
                return
            fi
        fi
    fi

    echo -e "${YELLOW}请选择你的智谱套餐类型:${NC}"
    echo "  1) Coding 套餐 (接口: open.bigmodel.cn/api/coding/paas/v4)"
    echo "  2) 标准套餐 (接口: open.bigmodel.cn/api/paas/v4)"
    echo ""
    read -p "请输入选项 [1/2，默认 1]: " plan_choice
    plan_choice=${plan_choice:-1}

    case $plan_choice in
        1) API_BASE="https://open.bigmodel.cn/api/coding/paas/v4"; success "已选择 Coding 套餐" ;;
        2) API_BASE="https://open.bigmodel.cn/api/paas/v4"; success "已选择标准套餐" ;;
        *) fatal "无效选项" ;;
    esac

    echo ""
    read -p "请输入你的智谱 API Key: " api_key
    if [[ -z "$api_key" ]]; then
        fatal "API Key 不能为空"
    fi
    API_KEY="$api_key"
    success "API Key 已设置"

    echo ""
    echo -e "${YELLOW}请选择模型:${NC}"
    echo "  1) glm-5.1 (默认)"
    echo "  2) glm-4-plus"
    echo "  3) glm-4-flash"
    echo ""
    read -p "请输入选项 [1/2/3，默认 1]: " model_choice
    model_choice=${model_choice:-1}

    case $model_choice in
        1) MODEL="glm-5.1" ;;
        2) MODEL="glm-4-plus" ;;
        3) MODEL="glm-4-flash" ;;
        *) MODEL="glm-5.1" ;;
    esac
    success "模型: $MODEL"

    echo ""
    read -p "litellm 服务端口 [默认 4000]: " port_input
    LITELLM_PORT=${port_input:-4000}

    if lsof -i :${LITELLM_PORT} -t &>/dev/null; then
        warn "端口 ${LITELLM_PORT} 已被占用"
        read -p "是否停止占用进程并继续? [Y/n]: " kill_port
        kill_port=${kill_port:-Y}
        if [[ "$kill_port" =~ ^[Yy] ]]; then
            lsof -i :${LITELLM_PORT} -t | xargs kill 2>/dev/null
            sleep 2
        else
            fatal "端口冲突，安装终止"
        fi
    fi
    success "端口: $LITELLM_PORT"

    echo ""
    read -p "是否设置开机自启? [Y/n，默认 Y]: " auto_start
    auto_start=${auto_start:-Y}
    AUTO_START=false
    if [[ "$auto_start" =~ ^[Yy] ]]; then
        AUTO_START=true
    fi
}

generate_configs() {
    info "====== 生成配置文件 ======"

    mkdir -p "$LITELLM_CONFIG_DIR"
    mkdir -p "$CODEX_CONFIG_DIR"

    cat > "$LITELLM_CONFIG_DIR/litellm-config.yaml" <<EOF
model_list:
  - model_name: ${MODEL}
    litellm_params:
      model: custom_openai/${MODEL}
      api_base: ${API_BASE}
      api_key: ${API_KEY}
EOF
    success "litellm 配置: $LITELLM_CONFIG_DIR/litellm-config.yaml"

    cat > "$CODEX_CONFIG_DIR/config.toml" <<EOF
model_provider = "custom"
model = "${MODEL}"
model_reasoning_effort = "high"
disable_response_storage = true

[model_providers]
[model_providers.custom]
name = "custom"
wire_api = "responses"
requires_openai_auth = true
base_url = "http://127.0.0.1:${LITELLM_PORT}"
EOF
    success "Codex 配置: $CODEX_CONFIG_DIR/config.toml"

    cat > "$CODEX_CONFIG_DIR/auth.json" <<EOF
{
  "OPENAI_API_KEY": "${API_KEY}"
}
EOF
    success "Codex 认证: $CODEX_CONFIG_DIR/auth.json"
}

patch_litellm() {
    info "====== Patch litellm Bug ======"

    $PYTHON_BIN "$SCRIPT_DIR/patch/patch_litellm.py" || fatal "Patch 失败，请查看上方错误信息"

    success "litellm Bug 修复完成"
}

setup_launch_agent() {
    if [[ "$AUTO_START" != "true" ]]; then
        info "跳过开机自启设置"
        return
    fi

    info "====== 设置开机自启 ======"

    mkdir -p "$LAUNCH_AGENTS_DIR"

    if [[ -f "$LAUNCH_AGENTS_DIR/$PLIST_NAME.plist" ]] && launchctl list "$PLIST_NAME" &>/dev/null; then
        launchctl unload "$LAUNCH_AGENTS_DIR/$PLIST_NAME.plist" 2>/dev/null || true
    fi

    cat > "$LAUNCH_AGENTS_DIR/$PLIST_NAME.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_NAME}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${LITELLM_BIN}</string>
        <string>--config</string>
        <string>${LITELLM_CONFIG_DIR}/litellm-config.yaml</string>
        <string>--port</string>
        <string>${LITELLM_PORT}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/litellm.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/litellm_error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$(dirname $LITELLM_BIN):/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
EOF

    launchctl load "$LAUNCH_AGENTS_DIR/$PLIST_NAME.plist" 2>/dev/null
    success "开机自启已设置 (LaunchAgent)"
}

start_litellm() {
    info "====== 启动 litellm 服务 ======"

    if lsof -i :${LITELLM_PORT} -t &>/dev/null; then
        info "端口 ${LITELLM_PORT} 已被占用，先停止 ..."
        lsof -i :${LITELLM_PORT} -t | xargs kill 2>/dev/null
        sleep 2
    fi

    if [[ "$AUTO_START" == "true" ]]; then
        if ! launchctl list "$PLIST_NAME" &>/dev/null; then
            launchctl load "$LAUNCH_AGENTS_DIR/$PLIST_NAME.plist" 2>/dev/null
        fi
    else
        nohup "$LITELLM_BIN" --config "$LITELLM_CONFIG_DIR/litellm-config.yaml" --port "$LITELLM_PORT" > /tmp/litellm.log 2>&1 &
    fi

    info "等待服务启动 ..."
    local started=false
    for i in $(seq 1 20); do
        if curl -s "http://127.0.0.1:${LITELLM_PORT}/health" &>/dev/null; then
            started=true
            break
        fi
        sleep 1
    done

    if [[ "$started" != "true" ]]; then
        error "litellm 启动超时，日志:"
        tail -20 /tmp/litellm.log 2>/dev/null
        echo ""
        echo "你可以稍后手动启动: ~/start_litellm.sh"
        echo "或查看日志: cat /tmp/litellm.log"
        return
    fi
    success "litellm 服务已启动"
}

verify() {
    info "====== 验证安装 ======"

    HEALTH=$(curl -s "http://127.0.0.1:${LITELLM_PORT}/health" 2>/dev/null)
    if echo "$HEALTH" | grep -q '"healthy_count"'; then
        HEALTHY=$(echo "$HEALTH" | $PYTHON_BIN -c "import sys,json; print(json.load(sys.stdin)['healthy_count'])" 2>/dev/null)
        success "litellm 健康检查通过 (healthy: ${HEALTHY:-?})"
    else
        warn "litellm 健康检查失败，请查看日志: /tmp/litellm.log"
        return
    fi

    info "测试 Responses API 桥接 ..."
    RESPONSE=$(curl -s -X POST "http://127.0.0.1:${LITELLM_PORT}/responses" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${API_KEY}" \
        -d "{\"model\":\"${MODEL}\",\"input\":\"你好\",\"stream\":false}" 2>/dev/null)

    if echo "$RESPONSE" | grep -q '"output"'; then
        success "Responses API 桥接测试通过！GLM 已正常响应"
    else
        warn "Responses API 桥接测试失败，请检查配置和 API Key"
        echo "  响应: $(echo "$RESPONSE" | head -c 300)"
    fi
}

install_scripts() {
    info "====== 安装辅助脚本 ======"

    sed -e "s|__PYTHON_BIN__|${PYTHON_BIN}|g" \
        -e "s|__LITELLM_BIN__|${LITELLM_BIN}|g" \
        -e "s|__LITELLM_PORT__|${LITELLM_PORT}|g" \
        "$SCRIPT_DIR/scripts/start_litellm.sh" > "$HOME/start_litellm.sh"
    chmod +x "$HOME/start_litellm.sh"
    success "启动脚本: ~/start_litellm.sh"

    sed -e "s|__LITELLM_PORT__|${LITELLM_PORT}|g" \
        "$SCRIPT_DIR/scripts/stop_litellm.sh" > "$HOME/stop_litellm.sh"
    chmod +x "$HOME/stop_litellm.sh"
    success "停止脚本: ~/stop_litellm.sh"
}

print_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}              安装配置完成！                      ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "完整链路: Codex Desktop (Responses API) → litellm (:${LITELLM_PORT}) → 智谱 GLM (Chat Completions)"
    echo ""
    echo "配置文件:"
    echo "  litellm 配置:  $LITELLM_CONFIG_DIR/litellm-config.yaml"
    echo "  Codex 配置:    $CODEX_CONFIG_DIR/config.toml"
    echo "  Codex 认证:    $CODEX_CONFIG_DIR/auth.json"
    echo "  litellm 日志:  /tmp/litellm.log"
    if [[ -n "$BACKUP_DIR" ]]; then
        echo "  旧配置备份:    $BACKUP_DIR"
    fi
    echo ""
    echo "常用命令:"
    echo "  启动 litellm:  ~/start_litellm.sh"
    echo "  停止 litellm:  ~/stop_litellm.sh"
    echo "  查看日志:      cat /tmp/litellm.log"
    if [[ "$AUTO_START" == "true" ]]; then
        echo "  停止开机自启:  launchctl unload ~/Library/LaunchAgents/$PLIST_NAME.plist"
        echo "  恢复开机自启:  launchctl load ~/Library/LaunchAgents/$PLIST_NAME.plist"
    fi
    echo ""
    echo -e "${YELLOW}下一步: 完全退出 Codex Desktop 再重新打开，即可使用 GLM 模型！${NC}"
    echo ""
}

main() {
    banner
    preflight_check
    find_python
    backup_existing
    install_litellm
    ask_config
    generate_configs
    patch_litellm
    setup_launch_agent
    start_litellm
    verify
    install_scripts
    print_summary
}

main
