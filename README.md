# Intent Compiler

[English](README.md) | [简体中文](README.zh-CN.md)

Compile vague, compressed requirements—including requests built on incorrect causal assumptions—into a verifiable Intent IR before handing them to planning and coding agents.

For example:

> "Slightly optimize the homepage."

Intent Compiler does not immediately start changing the UI. It expands candidate interpretations, reads repository evidence, separates the Problem / Cause Hypothesis / Requested Action, estimates the affected files and migration scope, and decides whether to proceed or ask a clarifying question.

## Quick install

On Windows, double-click [`install.cmd`](install.cmd). By default, it installs both the GPT/Codex and Claude Code versions.

You can also select a target from PowerShell:

```powershell
.\install.ps1 -Target all
.\install.ps1 -Target gpt
.\install.ps1 -Target claude
```

On macOS or Linux:

```bash
./install.sh all
```

Start a new agent session after installation:

- ChatGPT / Codex: use `$compile-intent`, or describe an ambiguous request and let the skill trigger automatically.
- Claude Code: use `/intent-compiler:compile-intent`, or let Claude trigger it automatically from the request.

## Quick uninstall

On Windows, double-click [`uninstall.cmd`](uninstall.cmd). By default, it removes both the GPT/Codex and Claude Code versions.

You can also remove a specific target or preview the operation first:

```powershell
.\uninstall.ps1 -Target all
.\uninstall.ps1 -Target gpt
.\uninstall.ps1 -Target claude
.\uninstall.ps1 -Target all -DryRun
```

On macOS or Linux:

```bash
./uninstall.sh all
```

The uninstaller removes only the artifacts and registry entries created for Intent Compiler. It preserves this source repository and other plugins. It updates the personal Codex marketplace in place without creating a persistent copy of other marketplace entries. Claude Code is removed through its official uninstall command, while orphaned cache entries are left to Claude's normal cache cleanup process.

## Supported platforms

- ChatGPT and Codex: native `.codex-plugin/plugin.json` plus an Agent Skill.
- Claude Code: native `.claude-plugin/plugin.json` plus a local plugin marketplace.
- Both platforms share the same `skills/compile-intent/SKILL.md`, Intent IR schema, decision policy, and validation script.

On Windows, the installer tries the Codex CLI first. If the bundled Codex CLI is unavailable, it copies the plugin into the personal plugin directory and registers a personal marketplace, so one-click installation still works. Claude Code uses its official marketplace and plugin CLI workflow.

## Manual installation

Codex:

```powershell
$IntentCompilerRepo = (Resolve-Path .).Path
codex plugin marketplace add $IntentCompilerRepo
codex plugin add intent-compiler@intent-compiler-local
```

Claude Code:

```powershell
$IntentCompilerRepo = (Resolve-Path .).Path
claude plugin marketplace add $IntentCompilerRepo --scope user
claude plugin install intent-compiler@intent-compiler-plugins --scope user
```

## Intent IR validation

```powershell
python .\plugins\intent-compiler\skills\compile-intent\scripts\intent_ir.py validate <intent-ir.json>
python .\plugins\intent-compiler\skills\compile-intent\scripts\intent_ir.py assess <intent-ir.json>
```

The plugin requires no API key and does not connect to external services. It uses only read-only project evidence already authorized for the agent when resolving intent; any later code changes remain subject to the current agent's permissions and approval rules.

## Privacy safeguards

- Installation ownership markers contain only a fixed plugin identifier and format version—never a source path, username, or timestamp.
- Installer-owned console messages do not print absolute local paths. Output from platform CLIs is suppressed during path-bearing operations and replaced with generic success or failure messages.
- Personal marketplace files are updated without persistent `.bak` copies.
- Intent IR must be sanitized before it is displayed or saved: secrets and personal identifiers are redacted, logs and feedback are summarized, timestamps are minimized, and source locations are repository-relative.
- `.gitignore` excludes common credential files, local databases, logs, backups, generated Intent IR, editor state, and archives that may preserve filesystem metadata.

Codex and Claude may keep their own local plugin registry as part of normal platform operation. Treat those user-level configuration directories as private and do not publish them. This repository does not copy their contents into its source tree.
