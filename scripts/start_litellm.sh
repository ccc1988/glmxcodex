#!/bin/bash

PYTHON_BIN="__PYTHON_BIN__"
LITELLM_BIN="__LITELLM_BIN__"
CONFIG_FILE="$HOME/.claude/litellm-config.yaml"
PORT="__LITELLM_PORT__"
LOG_FILE="/tmp/litellm.log"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "错误: 找不到配置文件 $CONFIG_FILE"
    echo "请先运行 install.sh 进行安装配置"
    exit 1
fi

if [[ ! -x "$LITELLM_BIN" ]]; then
    echo "错误: litellm 可执行文件不存在: $LITELLM_BIN"
    echo "请重新运行 install.sh"
    exit 1
fi

if lsof -i :${PORT} -t &>/dev/null; then
    echo "litellm 已在运行 (端口 ${PORT})，先停止..."
    lsof -i :${PORT} -t | xargs kill 2>/dev/null
    sleep 2
fi

echo "正在启动 litellm (端口 ${PORT})..."
nohup ${LITELLM_BIN} --config ${CONFIG_FILE} --port ${PORT} > ${LOG_FILE} 2>&1 &

echo "等待服务启动..."
for i in $(seq 1 15); do
    if curl -s "http://127.0.0.1:${PORT}/health" &>/dev/null; then
        echo "litellm 启动成功！"
        echo "  端口: ${PORT}"
        echo "  日志: ${LOG_FILE}"
        exit 0
    fi
    sleep 1
done

echo "litellm 启动超时，请查看日志: ${LOG_FILE}"
echo "最后 10 行日志:"
tail -10 ${LOG_FILE} 2>/dev/null
exit 1
