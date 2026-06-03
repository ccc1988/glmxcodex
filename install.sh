#!/bin/bash
set -e

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

info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

banner() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}        Codex + 智谱 GLM 一键安装配置工具        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}   Codex Desktop → litellm → 智谱 GLM (GLM-5.1)  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_os() {
    if [[ "$(uname)" != "Darwin" ]]; then
        error "本工具目前仅支持 macOS 系统"
    fi
    success "操作系统: macOS"
}

check_python() {
    local candidates=(
        "/opt/miniconda3/bin/python3"
        "$HOME/miniconda3/bin/python3"
        "/opt/homebrew/bin/python3"
        "/usr/local/bin/python3"
    )

    PYTHON_BIN=""

    for p in "${candidates[@]}"; do
        if [[ -x "$p" ]]; then
            local ver=$($p -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
            local major=$(echo "$ver" | cut -d. -f1)
            local minor=$(echo "$ver" | cut -d. -f2)
            if [[ "$major" -eq 3 && "$minor" -ge 10 && "$minor" -le 13 ]]; then
                PYTHON_BIN="$p"
                break
            else
                warn "跳过 $p (版本 $ver，需要 3.10~3.13)"
            fi
        fi
    done

    if [[ -z "$PYTHON_BIN" ]]; then
        if command -v python3 &>/dev/null; then
            PYTHON_BIN=$(command -v python3)
            local ver=$($PYTHON_BIN -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
            local minor=$(echo "$ver" | cut -d. -f2)
            if [[ "$minor" -gt 13 ]]; then
                error "系统 Python 版本为 $ver，litellm 依赖的 orjson 不支持 Python 3.14+。请安装 Python 3.10~3.13 (推荐 Miniconda: https://docs.conda.io/en/latest/miniconda.html)"
            fi
        else
            error "未找到 python3，请先安装 Python 3.10~3.13 (推荐 Miniconda: https://docs.conda.io/en/latest/miniconda.html)"
        fi
    fi

    PYTHON_VERSION=$($PYTHON_BIN -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    success "Python 版本: $PYTHON_VERSION ($PYTHON_BIN)"
}

check_pip() {
    if $PYTHON_BIN -m pip --version &>/dev/null; then
        success "pip 可用"
    else
        error "pip 不可用，请先安装 pip"
    fi
}

install_litellm() {
    info "检查 litellm ..."
    if $PYTHON_BIN -c "import litellm" 2>/dev/null; then
        LITELLM_VERSION=$($PYTHON_BIN -c "import importlib.metadata; print(importlib.metadata.version('litellm'))")
        success "litellm 已安装，版本: $LITELLM_VERSION"
    else
        info "正在安装 litellm[proxy] ..."
        $PYTHON_BIN -m pip install 'litellm[proxy]' || error "litellm 安装失败"
        success "litellm 安装完成"
    fi

    LITELLM_VERSION=$($PYTHON_BIN -c "import importlib.metadata; print(importlib.metadata.version('litellm'))")
    if $PYTHON_BIN -c "import packaging.version; exit(0 if packaging.version.Version('$LITELLM_VERSION') >= packaging.version.Version('1.66.3') else 1)" 2>/dev/null; then
        success "litellm 版本满足要求 (>= 1.66.3)"
    else
        warn "litellm 版本 $LITELLM_VERSION 低于 1.66.3，正在升级 ..."
        $PYTHON_BIN -m pip install --upgrade 'litellm[proxy]' || error "litellm 升级失败"
        success "litellm 升级完成"
    fi

    LITELLM_BIN=$($PYTHON_BIN -c "import shutil; print(shutil.which('litellm'))" 2>/dev/null)
    if [[ -z "$LITELLM_BIN" ]]; then
        LITELLM_BIN="$($PYTHON_BIN -c 'import sys; print(sys.prefix)')/bin/litellm"
    fi
    if [[ ! -x "$LITELLM_BIN" ]]; then
        LITELLM_BIN=$(dirname "$PYTHON_BIN")/litellm
    fi
    info "litellm 可执行文件: $LITELLM_BIN"
}

ask_config() {
    echo ""
    info "====== 配置信息 ======"
    echo ""

    echo -e "${YELLOW}请选择你的智谱套餐类型:${NC}"
    echo "  1) Coding 套餐 (接口: open.bigmodel.cn/api/coding/paas/v4)"
    echo "  2) 标准套餐 (接口: open.bigmodel.cn/api/paas/v4)"
    echo ""
    read -p "请输入选项 [1/2，默认 1]: " plan_choice
    plan_choice=${plan_choice:-1}

    case $plan_choice in
        1)
            API_BASE="https://open.bigmodel.cn/api/coding/paas/v4"
            success "已选择 Coding 套餐"
            ;;
        2)
            API_BASE="https://open.bigmodel.cn/api/paas/v4"
            success "已选择标准套餐"
            ;;
        *)
            error "无效选项"
            ;;
    esac

    echo ""
    read -p "请输入你的智谱 API Key: " api_key
    if [[ -z "$api_key" ]]; then
        error "API Key 不能为空"
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

    LITELLM_PATH=$($PYTHON_BIN -c "import litellm; print(litellm.__path__[0])")
    HANDLER_FILE="$LITELLM_PATH/responses/litellm_completion_transformation/handler.py"

    if [[ ! -f "$HANDLER_FILE" ]]; then
        error "找不到 handler.py: $HANDLER_FILE"
    fi

    if grep -q "client_metadata" "$HANDLER_FILE" 2>/dev/null && grep -q "Patch: 过滤" "$HANDLER_FILE" 2>/dev/null; then
        success "litellm 已经 patch 过，跳过"
        return
    fi

    $PYTHON_BIN "$SCRIPT_DIR/patch/patch_litellm.py" "$HANDLER_FILE" || error "Patch 失败"

    success "litellm Bug 已修复"
}

setup_launch_agent() {
    if [[ "$AUTO_START" != "true" ]]; then
        info "跳过开机自启设置"
        return
    fi

    info "====== 设置开机自启 ======"

    mkdir -p "$LAUNCH_AGENTS_DIR"

    if launchctl list "$PLIST_NAME" &>/dev/null; then
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
    for i in $(seq 1 15); do
        if curl -s "http://127.0.0.1:${LITELLM_PORT}/health" &>/dev/null; then
            break
        fi
        sleep 1
    done
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
        echo "  响应: $(echo "$RESPONSE" | head -c 200)"
    fi
}

copy_scripts() {
    info "====== 安装辅助脚本 ======"

    cp "$SCRIPT_DIR/scripts/start_litellm.sh" "$HOME/start_litellm.sh"
    chmod +x "$HOME/start_litellm.sh"
    success "启动脚本: ~/start_litellm.sh"

    cp "$SCRIPT_DIR/scripts/stop_litellm.sh" "$HOME/stop_litellm.sh"
    chmod +x "$HOME/stop_litellm.sh"
    success "停止脚本: ~/stop_litellm.sh"
}

print_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}              🎉 安装配置完成！                   ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "完整链路: Codex Desktop (Responses API) → litellm (:${LITELLM_PORT}) → 智谱 GLM (Chat Completions)"
    echo ""
    echo "配置文件:"
    echo "  litellm 配置:  $LITELLM_CONFIG_DIR/litellm-config.yaml"
    echo "  Codex 配置:    $CODEX_CONFIG_DIR/config.toml"
    echo "  Codex 认证:    $CODEX_CONFIG_DIR/auth.json"
    echo "  litellm 日志:  /tmp/litellm.log"
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
    check_os
    check_python
    check_pip
    install_litellm
    ask_config
    generate_configs
    patch_litellm
    setup_launch_agent
    start_litellm
    verify
    copy_scripts
    print_summary
}

main
