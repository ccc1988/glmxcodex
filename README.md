# Codex + 智谱 GLM 一键配置

让 [Codex Desktop](https://github.com/openai/codex) 通过 [litellm](https://github.com/BerriAI/litellm) 协议翻译，使用智谱 GLM 大模型。

## 架构

```
Codex Desktop (Responses API) → litellm (:4000) → 智谱 GLM (Chat Completions)
```

Codex 使用 OpenAI Responses API 协议，而智谱 GLM 只支持 Chat Completions API。litellm 作为中间代理，负责协议转换。

## 前置条件

- macOS
- Python 3.10+
- [智谱 API Key](https://open.bigmodel.cn/)（Coding 套餐或标准套餐均可）
- [Codex Desktop](https://github.com/openai/codex) 已安装

## 一键安装

```bash
git clone https://github.com/YOUR_USERNAME/codex-glm.git
cd codex-glm
./install.sh
```

安装脚本会自动完成：
1. 检查并安装 litellm（含 proxy 依赖）
2. 交互式引导配置（API Key、套餐类型、模型选择）
3. 生成所有配置文件
4. Patch litellm 的两个已知 Bug
5. 设置开机自启（macOS LaunchAgent）
6. 启动服务并验证

安装完成后，**完全退出 Codex Desktop 再重新打开**，即可使用 GLM 模型。

## 手动配置（高级）

如果你不想使用一键脚本，可以参考 [config/](config/) 目录下的模板文件手动配置：

| 文件 | 路径 | 说明 |
|------|------|------|
| litellm-config.yaml | `~/.claude/litellm-config.yaml` | litellm 代理配置 |
| config.toml | `~/.codex/config.toml` | Codex 模型配置 |
| auth.json | `~/.codex/auth.json` | Codex API Key |

### 关键配置说明

1. **模型前缀必须用 `custom_openai/`**，不能用 `openai/`。`openai/` 前缀会让 litellm 原样转发 Responses API 请求，导致 404。

2. **Coding 套餐 vs 标准套餐**：Coding 套餐用 `open.bigmodel.cn/api/coding/paas/v4`，标准套餐用 `open.bigmodel.cn/api/paas/v4`。

3. **litellm Bug Patch**：litellm 的 Responses API 桥接有两个未修复的 Bug，必须手动 patch：
   - Bug 1：`client_metadata` 等参数未过滤，导致底层客户端报错
   - Bug 2：非 `function` 类型工具未过滤，GLM 不支持会报错

   运行 `python3 patch/patch_litellm.py <handler.py路径>` 即可修复。

## 常用命令

```bash
# 启动 litellm
~/start_litellm.sh

# 停止 litellm
~/stop_litellm.sh

# 查看日志
cat /tmp/litellm.log

# 管理开机自启
launchctl unload ~/Library/LaunchAgents/com.litellm.proxy.plist  # 停止自启
launchctl load ~/Library/LaunchAgents/com.litellm.proxy.plist    # 恢复自启
```

## 卸载

```bash
./uninstall.sh
```

## 项目结构

```
codex-glm/
├── install.sh                  # 一键安装脚本
├── uninstall.sh                # 卸载脚本
├── LICENSE                     # MIT 许可证
├── config/                     # 配置模板
│   ├── litellm-config.yaml.template
│   ├── config.toml.template
│   └── auth.json.template
├── patch/                      # litellm Bug 修复
│   └── patch_litellm.py
├── scripts/                    # 辅助脚本
│   ├── start_litellm.sh
│   └── stop_litellm.sh
└── service/                    # macOS 服务配置（由 install.sh 自动生成）
```

## 支持的模型

| 模型 | 说明 |
|------|------|
| glm-5.1 | 智谱最新模型（默认） |
| glm-4-plus | GLM-4 增强版 |
| glm-4-flash | GLM-4 快速版 |

## 常见问题

### Q: Codex 报错 "Unexpected keyword argument 'client_metadata'"
A: litellm 的 Bug 未 patch。运行 `python3 patch/patch_litellm.py <handler.py路径>` 修复。

### Q: Codex 报错工具相关错误
A: 同上，非 function 类型工具未过滤。patch 即可解决。

### Q: litellm 启动报 KeyError: 'litellm_params'
A: YAML 缩进错误。确保 `litellm_params` 在 `model_name` 下缩进 2 空格。

### Q: 电脑重启后 Codex 连不上
A: 检查 litellm 是否在运行：`lsof -i :4000`。如果没有，运行 `~/start_litellm.sh`。

## 致谢

- [litellm](https://github.com/BerriAI/litellm) - LLM 代理网关
- [智谱 GLM](https://open.bigmodel.cn/) - 大语言模型
- [Codex](https://github.com/openai/codex) - AI 编程助手

## License

[MIT](LICENSE)
