# Intent Compiler（意图编译器）

[English](README.md) | [简体中文](README.zh-CN.md)

把含糊、压缩、带有错误因果假设的需求，编译成可验证的 Intent IR，再交给规划和编码 Agent。

例如：

> “稍微优化一下首页。”

Intent Compiler 不会直接开始改 UI。它会展开候选意图、读取代码库证据、区分 Problem / Cause Hypothesis / Requested Action、估算受影响文件与迁移范围，并决定应该执行还是追问。

## 一键安装

Windows：双击 [`install.cmd`](install.cmd)，默认同时安装 GPT/Codex 与 Claude Code 版本。

也可以从 PowerShell 选择平台：

```powershell
.\install.ps1 -Target all
.\install.ps1 -Target gpt
.\install.ps1 -Target claude
```

macOS / Linux：

```bash
./install.sh all
```

安装后开启新的 Agent 会话：

- ChatGPT / Codex：使用 `$compile-intent`，或直接描述含糊需求让它自动触发。
- Claude Code：使用 `/intent-compiler:compile-intent`，也可由 Claude 根据需求自动触发。

## 一键卸载

Windows：双击 [`uninstall.cmd`](uninstall.cmd)，默认同时卸载 GPT/Codex 与 Claude Code 版本。

也可以只卸载指定平台，或先预览将发生的操作：

```powershell
.\uninstall.ps1 -Target all
.\uninstall.ps1 -Target gpt
.\uninstall.ps1 -Target claude
.\uninstall.ps1 -Target all -DryRun
```

macOS / Linux：

```bash
./uninstall.sh all
```

卸载器只删除 Intent Compiler 的安装产物和注册信息，保留本源码仓库及其他插件。它会原地更新 Codex 个人 marketplace，不会为其他 marketplace 条目创建持久副本。Claude Code 使用官方卸载命令，其孤立缓存会按 Claude 的缓存清理机制延迟回收。

## 支持范围

- ChatGPT 与 Codex：原生 `.codex-plugin/plugin.json` + Agent Skill。
- Claude Code：原生 `.claude-plugin/plugin.json` + 本地 plugin marketplace。
- 两个平台共用同一份 `skills/compile-intent/SKILL.md`、Intent IR Schema、决策策略和校验脚本。

Windows 安装器会优先调用 Codex CLI。若打包版 Codex CLI 不可用，则自动复制插件到个人插件目录并注册个人 marketplace，因此仍可一键完成安装。Claude Code 使用官方 marketplace 与 plugin CLI 安装流程。

## 手动安装

Codex：

```powershell
$IntentCompilerRepo = (Resolve-Path .).Path
codex plugin marketplace add $IntentCompilerRepo
codex plugin add intent-compiler@intent-compiler-local
```

Claude Code：

```powershell
$IntentCompilerRepo = (Resolve-Path .).Path
claude plugin marketplace add $IntentCompilerRepo --scope user
claude plugin install intent-compiler@intent-compiler-plugins --scope user
```

## Intent IR 校验

```powershell
python .\plugins\intent-compiler\skills\compile-intent\scripts\intent_ir.py validate <intent-ir.json>
python .\plugins\intent-compiler\skills\compile-intent\scripts\intent_ir.py assess <intent-ir.json>
```

插件不需要 API Key，也不会连接外部服务。它只使用 Agent 已获授权的只读项目证据来解析意图；后续是否修改代码仍遵循当前 Agent 的权限与审批规则。

## 隐私保护

- 安装归属标记只包含固定插件标识和格式版本，不记录源码路径、用户名或安装时间。
- 安装器自身的终端信息不会打印本地绝对路径；可能携带路径的平台 CLI 输出会被抑制，并替换为通用的成功或失败信息。
- 更新个人 marketplace 时不会生成持久的 `.bak` 副本。
- Intent IR 在显示或保存前必须脱敏：密钥和个人标识会被替换，日志与反馈只做摘要，时间精度会被最小化，证据位置使用仓库相对路径。
- `.gitignore` 会排除常见凭据文件、本地数据库、日志、备份、生成的 Intent IR、编辑器状态，以及可能保留文件系统元数据的压缩包。

Codex 和 Claude 在正常运行时可能维护各自的本地插件注册信息。应将这些用户级配置目录视为私有内容，不要公开。本仓库不会把其中的内容复制进源码树。
