# Codex + 智谱 GLM / DeepSeek 多后端代理

让 [Codex Desktop](https://github.com/openai/codex) 通过本地代理使用智谱 GLM、DeepSeek 等非 OpenAI 模型。

## 架构

```
Codex Desktop (Responses API)
        │
        ▼
Multi-Backend Proxy (:18765)
        │
        ├─ glm-*      → 智譜 GLM Chat Completions API
        ├─ deepseek-* → DeepSeek Chat Completions API
        └─ gpt-*, o*  → OpenAI Responses API (直接转发)
```

## 前置条件

- macOS
- Python 3.x（无特殊版本要求，仅用标准库）
- [智谱 API Key](https://open.bigmodel.cn/)
- [Codex Desktop](https://github.com/openai/codex) 已安装

## 快速使用

```bash
# 配置 API Key（已有 litellm-config.yaml 会自动读取）
export GLM_API_KEY="你的智谱Key"

# 启动代理
cd proxy && ./start.sh

# 配置 Codex：编辑 ~/.codex/config.toml
# model_provider = "custom"
# model = "glm-5.1"
# base_url = "http://127.0.0.1:18765/v4"
# wire_api = "responses"
# model_catalog_json = "/Users/xxx/.codex/cc-switch-model-catalog.json"
```

然后重启 Codex Desktop，选择 GLM-5.1 即可使用。

## 多模型切换

代理根据模型名前缀自动路由：

| 模型 | → 后端 | API Key 来源 |
|------|--------|-------------|
| `glm-5.1`, `glm-5` | 智譜 GLM | `~/.claude/litellm-config.yaml` 或环境变量 |
| `deepseek-chat` | DeepSeek | `~/.claude/proxy-config.json` |
| `gpt-*`, `o*` | OpenAI | `~/.claude/proxy-config.json` |

DeepSeek 和 OpenAI 的 Key 配置（`~/.claude/proxy-config.json`）：
```json
{
  "backends": {
    "deepseek": { "api_key": "你的Key" },
    "openai": { "api_key": "你的Key" }
  }
}
```

## 开机自启

```bash
launchctl load ~/Library/LaunchAgents/com.codex-glm.proxy.plist
```

## 项目结构

```
codex-glm/
├── README.md
├── install.sh                  # 一键安装（litellm 方式，历史保留）
├── uninstall.sh
├── proxy/                      # ★ 多后端代理（推荐使用）
│   ├── proxy.py                # 核心代理，支持 GLM/DeepSeek/OpenAI
│   ├── start.sh                # 启动脚本
│   └── stop.sh                 # 停止脚本
├── patch/
│   └── patch_litellm.py        # litellm 补丁（历史保留）
└── config/                     # litellm 配置模板（历史保留）
```

## 常见问题

### Q: Codex 模型选择器看不到 GLM
A: 需要 model_catalog_json 指向 cc-switch 格式的模型目录。可以使用 cc-switch 生成的 `~/.codex/cc-switch-model-catalog.json`。

### Q: 选了 GLM 但回复还是 GPT-5
A: 代理会自动替换 Codex 硬编码的 "based on GPT-5" 文字。如果仍然出现，检查 Codex 的 base_url 是否指向代理。

### Q: Codex++ / cc-switch 会覆盖配置
A: 是的。使用 GLM/DeepSeek 期间请关闭 Codex++ 和 cc-switch。

## 致谢

- [JichinX/codex-glm-proxy](https://github.com/JichinX/codex-glm-proxy) — 核心架构参考
- [glmxcodex](https://github.com/ccc1988/glmxcodex) — 原始 litellm 方案
- [智谱 GLM](https://open.bigmodel.cn/) / [DeepSeek](https://deepseek.com/)

## License

[MIT](LICENSE)
