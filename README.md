# autopilot-lead · 总控模式

让一个 Claude Code 会话当「总控」：派多个子代理工人在各自的 git worktree 里并行干活，审查员只读把关，顾问替你做日常判断，所有状态落在项目文件里（手册 / 台账 / 看板 / 队列），完成与待拍板推到群机器人。适合多条工作线、跨天推进、你大部分时间不在电脑前的项目。

> A Claude Code skill that turns one session into a "lead" orchestrating worktree-isolated sub-agents, with a read-only reviewer, a decision advisor, a hard-stop list, and all state kept in repo files. Docs are in Chinese.

## 需要
- [Claude Code](https://docs.claude.com/en/docs/claude-code)，能用子代理（`.claude/agents/`、`isolation: worktree`、`SendMessage`）
- git、bash、python3、curl
- macOS 或 Linux（`build-slot.sh` 用 `flock`；Windows 请用 WSL）
- 可选：飞书 / Slack / Discord / 企业微信群机器人

## 安装
把本目录放进 Claude Code 的 skills 目录：
```bash
git clone https://github.com/fengyan3141/autopilot-lead.git ~/.claude/skills/autopilot-lead
```
然后在项目里对 Claude 说「按总控模式起项目」。

## 用法
- 起骨架（先预演，确认后加 `--apply`；已有文件一律跳过）：
  ```bash
  bash ~/.claude/skills/autopilot-lead/scripts/init.sh --project-dir "$PWD" --slug myapp --name 我的项目 \
    --branch main --slots "app:ios/,server:backend/" --notify slack
  ```
- 运行循环、硬停清单、审查清单：见 `SKILL.md` 与生成的 `docs/AUTOPILOT.md`。
- 通知接法：`references/notify.md`。踩过的坑：`references/lessons.md`。

## 目录
```
SKILL.md                 总控怎么起、怎么跑
templates/               手册、三种代理、压缩保留段
scripts/init.sh          生成骨架
scripts/notify.sh        群机器人通知
scripts/build-slot.sh    重活排队器
references/              坑与对策、通知接法
```

## 许可

MIT © 2026 枫焱，见 [LICENSE](LICENSE)。
