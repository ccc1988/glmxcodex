# Codex Multi-Backend Proxy 🚀

让 [OpenAI Codex Desktop](https://github.com/openai/codex) 使用**智谱 GLM、DeepSeek** 等非 OpenAI 模型。

- 纯 Python 标准库，**零外部依赖**
- 一个 `./install.sh` 完成全部配置
- 自动路由：选 GLM 走智譜，选 DeepSeek 走 DeepSeek，选 GPT 走 OpenAI

## 架构

```
Codex Desktop ──→ Proxy (:18765) ──→ glm-*      → 智譜 Chat Completions
                                   ├─ deepseek-* → DeepSeek Chat Completions
                                   └─ gpt-*, o*  → OpenAI Responses
```

## 快速开始

### 1. 克隆

```bash
git clone https://github.com/ccc1988/glmxcodex.git
cd glmxcodex
```

### 2. 安装（交互式输入 API Key）

```bash
./install.sh
```

自动完成：环境检测 → 备份旧配置 → 写入 API Key → 安装模型目录 → 配置 Codex → 启动代理。

### 3. 重启 Codex

退出并重新打开 Codex Desktop，模型下拉菜单选择 **GLM-5.1**。

> 出问题了？运行 `./proxy/fix.sh` 一键诊断修复。

## 命令

| 命令 | 用途 |
|------|------|
| `./install.sh` | 一键安装 |
| `./proxy/fix.sh` | 一键诊断修复 |
| `./proxy/start.sh` | 启动代理 |
| `./proxy/stop.sh` | 停止代理 |
| `./uninstall.sh` | 卸载 |
| `tail -f /tmp/codex-glm-proxy.log` | 查看日志 |

## 多模型

代理根据模型名前缀自动路由：

| 模型 | → 后端 | Key 来源 |
|------|--------|---------|
| `glm-5.1`, `glm-5` | 智譜 | 安装时输入 / 环境变量 `GLM_API_KEY` |
| `deepseek-chat`, `deepseek-v4-flash` | DeepSeek | 环境变量 `DEEPSEEK_API_KEY` |
| `gpt-*`, `o*` | OpenAI | 环境变量 `OPENAI_API_KEY_DIRECT` |

或编辑 `~/.config/codex-glm/proxy-config.json`：

```json
{
  "backends": {
    "glm": { "api_key": "sk-xxx" },
    "deepseek": { "api_key": "sk-xxx" },
    "openai": { "api_key": "sk-xxx" }
  }
}
```

## 操作系统

| 系统 | 安装 | 自启 |
|------|------|------|
| macOS | `./install.sh` | LaunchAgent |
| Linux | `./install.sh` | systemd |
| Windows | `python proxy/proxy.py` | Task Scheduler / start.bat |

## 常见问题

<details>
<summary>选了 GLM 回复还是 GPT？</summary>
代理自动替换 Codex 硬编码的提示词。确认 config.toml 中 <code>base_url</code> 是 <code>http://127.0.0.1:18765/v4</code>。
</details>

<details>
<summary>模型选择器看不到模型？</summary>
运行 <code>./proxy/fix.sh</code>。或检查 config.toml 是否包含 <code>model_reasoning_effort</code> 和 <code>personality</code> 字段。
</details>

<details>
<summary>Windows？</summary>
<code>python proxy/proxy.py</code> 直接运行。代理纯 Python，跨平台。
</details>

## 项目结构

```
├── install.sh / uninstall.sh
├── README.md
├── proxy/
│   ├── proxy.py          ★ 核心代理
│   ├── fix.sh            一键修复
│   ├── start.sh / stop.sh / start.bat
├── config/
│   └── model-catalog.json  ★ 模型目录模板
```

## 参考

- 模型目录格式来自 [cc-switch](https://github.com/EINDEX/cc-switch)（Codex 多模型切换工具，可选配合使用）
- 代理架构参考 [JichinX/codex-glm-proxy](https://github.com/JichinX/codex-glm-proxy)

## License

[MIT](LICENSE)
