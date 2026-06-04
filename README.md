# Codex Multi-Backend Proxy 🚀

让 [OpenAI Codex Desktop](https://github.com/openai/codex) 使用**智谱 GLM、DeepSeek** 等非 OpenAI 模型。一个本地代理，零外部依赖。

## 架构

```
Codex Desktop (Responses API)
        │
        ▼
Multi-Backend Proxy (:18765)  ← 纯 Python，零依赖
        │
        ├─ glm-*      → 智譜 Chat Completions
        ├─ deepseek-* → DeepSeek Chat Completions
        └─ gpt-*, o*  → OpenAI Responses (直通)
```

## 快速开始

```bash
# 1. 克隆
git clone https://github.com/ccc1988/glmxcodex.git
cd glmxcodex

# 2. 安装（交互式输入 API Key）
./install.sh

# 3. 配置 Codex（编辑 ~/.codex/config.toml）
# model_provider = "custom"
# model = "glm-5.1"
# base_url = "http://127.0.0.1:18765/v4"
# wire_api = "responses"
# model_catalog_json = "~/.codex/codex-glm-model-catalog.json"

# 4. 重启 Codex Desktop，选 GLM-5.1
```

## 操作系统支持

| 系统 | 安装 | 自动启动 | 状态 |
|------|------|---------|------|
| macOS | `./install.sh` | LaunchAgent | ✅ 完整支持 |
| Linux | `./install.sh` | systemd | ✅ 完整支持 |
| Windows | 手动 `python proxy/proxy.py` | 无（可自行注册服务） | ⚠️ 手动使用 |

## 多模型切换

代理根据模型名自动路由到对应后端：

| Codex 中选择的模型 | 实际后端 | 如何配置 API Key |
|-------------------|---------|-----------------|
| `glm-5.1`, `glm-5` | 智譜 GLM | 安装时输入，或 `export GLM_API_KEY=...` |
| `deepseek-chat` | DeepSeek | 安装时输入，或 `export DEEPSEEK_API_KEY=...` |
| `gpt-*`, `o*` | OpenAI | 安装时输入，或 `export OPENAI_API_KEY_DIRECT=...` |

无需重启代理，切换模型即可自动路由。

## 手动配置 API Key

编辑 `~/.config/codex-glm/proxy-config.json`：

```json
{
  "backends": {
    "glm": {
      "api_key": "你的智谱Key"
    },
    "deepseek": {
      "api_key": "你的DeepSeekKey"
    },
    "openai": {
      "api_key": "你的OpenAIKey"
    }
  }
}
```

也可以用环境变量：`GLM_API_KEY`、`DEEPSEEK_API_KEY`、`OPENAI_API_KEY_DIRECT`。

## 手动管理代理

```bash
# 启动
./proxy/start.sh

# 停止
./proxy/stop.sh

# 查看日志
tail -f /tmp/codex-glm-proxy.log

# 健康检查
curl http://localhost:18765/health
```

## 常见问题

<details>
<summary>选了 GLM 回复还是 GPT-5？</summary>
代理会自动替换 Codex 硬编码的 "based on GPT-5" 提示词。如仍有问题，检查 <code>base_url</code> 是否正确指向 <code>http://127.0.0.1:18765/v4</code>。
</details>

<details>
<summary>Codex 模型选择器看不到模型？</summary>
确保 <code>model_catalog_json</code> 指向正确的模型目录文件。安装脚本会自动生成 <code>~/.codex/codex-glm-model-catalog.json</code>。如果丢失，重新运行 <code>./install.sh</code> 即可。
</details>



<details>
<summary>Windows 怎么用？</summary>
<code>python proxy/proxy.py</code> 直接运行。或注册为 Windows 服务。代理本身纯 Python，跨平台。
</details>

## 项目结构

```
├── install.sh          # 跨平台安装脚本
├── uninstall.sh        # 卸载脚本
├── proxy/
│   ├── proxy.py        # ★ 核心代理（多后端路由）
│   ├── start.sh        # 启动 / 停止
│   └── stop.sh
├── patch/
│   └── patch_litellm.py
├── config/             # 配置模板
└── scripts/            # litellm 辅助脚本
```

## 致谢

- [JichinX/codex-glm-proxy](https://github.com/JichinX/codex-glm-proxy) — 核心架构参考
- [智谱 AI](https://open.bigmodel.cn/) / [DeepSeek](https://deepseek.com/) / [OpenAI](https://openai.com/)

## License

[MIT](LICENSE)
