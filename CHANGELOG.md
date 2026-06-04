# Changelog

## v1.1.5 — 2026-06-05

### 修复
- `uninstall.sh` 现在默认询问是否清除 API Key（`~/.config/codex-glm/`），解决重装后复用过期 Key 的问题
- 新增 `./uninstall.sh --all` 一键彻底卸载（含 Key + 模型目录）

### 新增
- 模型目录新增 DeepSeek-V4-Flash、DeepSeek-V4-Pro
- 模型目录新增 GPT-5、GPT-5 Mini、GPT-5 Nano

### 文档
- README 更新卸载命令说明和异常处理
- Skill 文档同步更新

---

## v1.1.4 — 2026-06-05

### 文档
- README 优化：一键安装/运维/异常处理/API Key 分节

## v1.1.3 — 2026-06-05

### 修复
- 改进 DeepSeek 提示词替换规则，明确身份声明

## v1.1.2 — 2026-06-05

### 文档
- README 重写，添加 cc-switch 参考链接和 fix.sh 命令表

## v1.1.1 — 2026-06-05

### 修复
- 模型目录模板改用 cp cc-switch 原文件，不用 json.dump 生成

## v1.1.0 — 2026-06-05

### 修复
- config.toml 缺 model_reasoning_effort 和 personality 导致模型不显示
