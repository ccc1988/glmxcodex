#!/bin/bash

LITELLM_BIN=$(command -v litellm 2>/dev/null || echo "")
if [[ -z "$LITELLM_BIN" ]]; then
    LITELLM_BIN="/opt/miniconda3/bin/litellm"
fi

CONFIG_FILE="$HOME/.claude/litellm-config.yaml"
PORT=${1:-4000}
LOG_FILE="/tmp/litellm.log"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "错误: 找不到配置文件 $CONFIG_FILE"
    echo "请先运行 install.sh 进行安装配置"
    exit 1
fi

if lsof -i :${PORT} -t &>/dev/null; then
    echo "litellm 已在运行 (端口 ${PORT})，先停止..."
    lsof -i :${PORT} -t | xargs kill 2>/dev/null
    sleep 2
fi

echo "正在启动 litellm (端口 ${PORT})..."
nohup ${LITELLM_BIN} --config ${CONFIG_FILE} --port ${PORT} > ${LOG_FILE} 2>&1 &

sleep 3

if lsof -i :${PORT} -t &>/dev/null; then
    echo "litellm 启动成功！"
    echo "  端口: ${PORT}"
    echo "  日志: ${LOG_FILE}"
else
    echo "litellm 启动失败，请查看日志: ${LOG_FILE}"
    exit 1
fi
