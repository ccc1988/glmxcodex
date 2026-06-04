# Codex Multi-Backend Proxy 🚀

让 [OpenAI Codex Desktop](https://github.com/openai/codex) 使用**智谱 GLM、DeepSeek** 等非 OpenAI 模型。

- 纯 Python 标准库，**零外部依赖**
- 一行安装，三行配置
- 自动路由：GLM → 智譜 | DeepSeek → DeepSeek | GPT → OpenAI

## 架构

```
Codex Desktop ──→ Proxy (:18765) ──→ glm-*      → 智譜
                                   ├─ deepseek-* → DeepSeek
                                   └─ gpt-*, o*  → OpenAI
```

---

## 一键安装

```bash
git clone https://github.com/ccc1988/glmxcodex.git && cd glmxcodex && ./install.sh
```

按提示输入 API Key，自动完成：环境检测 → 备份 → API Key → 模型目录 → Codex 配置 → 代理启动。

**重启 Codex Desktop**，选择 GLM-5.1 即可使用。

---

## 运行命令

| 命令 | 用途 |
|------|------|
| `./install.sh` | 全新安装 |
| `./proxy/fix.sh` | 一键诊断修复 |
| `./proxy/start.sh` | 启动代理 |
| `./proxy/stop.sh` | 停止代理 |
| `./uninstall.sh` | 卸载（默认保留 Key 以便重装） |
| `./uninstall.sh --all` | 彻底卸载（含 API Key） |

**日志和检查**：
```bash
tail -f /tmp/codex-glm-proxy.log          # 查看日志
curl http://localhost:18765/health        # 健康检查
grep "Model:" /tmp/codex-glm-proxy.log   # 看路由记录
```

---

## 异常处理

| 症状 | 解决 |
|------|------|
| 模型下拉空白 | `./proxy/fix.sh` 然后重启 Codex |
| 回复还是 GPT | 检查 config.toml 中 `base_url = "http://127.0.0.1:18765/v4"` |
| 401 / 令牌过期 | 更新 `~/.config/codex-glm/proxy-config.json` 中 API Key |
| 重装后 Key 未刷新 | `./uninstall.sh --all` 彻底清理后再 `./install.sh` |
| 端口 18765 被占 | `lsof -ti :18765 \| xargs kill -9 && ./proxy/start.sh` |
| cc-switch/Codex++ 干扰 | `pkill -9 CodexPlusPlus cc-switch` 关闭它们 |
| 代理启动失败 | `rm -f /tmp/codex-glm-proxy.pid && ./proxy/start.sh` |

---

## API Key 配置

编辑 `~/.config/codex-glm/proxy-config.json`：

```json
{
  "backends": {
    "glm": { "api_key": "智谱Key" },
    "deepseek": { "api_key": "DeepSeekKey" },
    "openai": { "api_key": "OpenAIKey" }
  }
}
```

或用环境变量：`GLM_API_KEY` / `DEEPSEEK_API_KEY` / `OPENAI_API_KEY_DIRECT`。

---

## 操作系统

| 系统 | 安装 | 自启 |
|------|------|------|
| macOS | `./install.sh` | LaunchAgent |
| Linux | `./install.sh` | systemd |
| Windows | `python proxy/proxy.py` | Task Scheduler / start.bat |

---

## 参考

- 模型目录格式来自 [cc-switch](https://github.com/EINDEX/cc-switch)
- 代理架构参考 [JichinX/codex-glm-proxy](https://github.com/JichinX/codex-glm-proxy)

## License

[MIT](LICENSE)
