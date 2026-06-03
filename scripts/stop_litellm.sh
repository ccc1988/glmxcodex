#!/bin/bash

PORT="__LITELLM_PORT__"

if lsof -i :${PORT} -t &>/dev/null; then
    echo "正在停止 litellm (端口 ${PORT})..."
    lsof -i :${PORT} -t | xargs kill 2>/dev/null
    sleep 2
    if lsof -i :${PORT} -t &>/dev/null; then
        echo "强制停止..."
        lsof -i :${PORT} -t | xargs kill -9 2>/dev/null
    fi
    echo "litellm 已停止"
else
    echo "litellm 未在运行"
fi

PLIST="$HOME/Library/LaunchAgents/com.litellm.proxy.plist"
if [[ -f "$PLIST" ]] && launchctl list com.litellm.proxy &>/dev/null; then
    echo "正在卸载 LaunchAgent..."
    launchctl unload "$PLIST" 2>/dev/null
    echo "LaunchAgent 已卸载"
fi
