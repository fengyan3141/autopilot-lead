---
name: autopilot-lead
description: 总控模式：让一个 Claude Code 会话当「总控」，派多个子代理工人在各自 git worktree 里并行干活，审查员只读把关、顾问替用户拍板，状态全部落在项目文件（手册 / 台账 / 看板 / 队列）里，完成与待拍板推群机器人（飞书 / Slack / Discord / 企业微信）。用于给新项目起这套骨架，或接手、续跑已有总控。当用户说「按总控模式起项目」「给这个项目也搭一个总控」「多个 agent 并行开发要有人统筹」「我不在电脑前也要能推进」「autopilot」「总控接着跑 / 压缩后续上」时触发。只是一次性把两三个独立任务并行跑完、或只想讨论多 Agent 怎么拆，不需要本 skill。
---

# 总控模式（autopilot-lead）

从一个真实的 iOS + 服务端项目（约 190 条拍板、上百个子代理任务）提炼。核心只有三件事，其余都是按需加的补丁：

1. **状态落文件，不落对话**：手册 `docs/AUTOPILOT.md` 里的台账、看板、队列是唯一真源，上下文压缩或换会话后从文件续上。
2. **干活、审查、拍板分给不同角色**：工人改代码不提交；审查员只读，结论只有「过 / 打回」；顾问替用户做判断、给结论不给选项；只有总控合并与 commit。
3. **硬停清单**：只有清单上的事等用户，其余总控自己定并记台账。这张表决定用户能放手到什么程度。

## 什么时候用

- 适合：多条工作线能并行（如客户端 / 服务端 / 文档）、要跨天推进、用户多数时间不在电脑前。
- 不适合：单个任务、一两个小时做得完——直接做，别搭架子。

## 模式 A：给新项目起骨架

1. **前提**：目标目录是 git 仓库；确认主干分支名；工作区有未提交改动先让用户决定是否提交（不替别人的改动做主）。
2. **一次问清**（缺什么问什么，已知的不问）：
   - 项目简称（slug，英文小写）与显示名；
   - 工作线（槽位）和各自能碰的目录，例如 `app:ios/,server:supabase/,docs:docs/`；
   - 硬停清单要不要在默认七类上增减（默认见模板 §1）；
   - 通知渠道：飞书 / Slack / Discord / 企业微信机器人 webhook，或不要通知（`--notify none`）。**让用户自己把 URL 写进 `~/.claude/autopilot/webhooks/<slug>`，不要贴进对话。**
3. **生成骨架**：先预演再写入，已存在的文件一律跳过、不覆盖。
   ```bash
   bash <本 skill 目录>/scripts/init.sh --project-dir <绝对路径> --slug <slug> --name <显示名> \
     --branch <主干> --slots "app:ios/,server:supabase/" \
     [--notify feishu|slack|discord|wecom|none] [--tz Asia/Shanghai]   # 预演
   bash <同上> ... --apply                                        # 写入
   ```
   生成：`docs/AUTOPILOT.md`、`docs/prompts/`、`.claude/agents/{reviewer,advisor,worker-<槽>}.md`、`.claude/autopilot.env`、`tools/build-slot.sh`、CLAUDE.md 里的 Compact Instructions 段。
4. **补项目专属内容**：每个 `worker-<槽>.md` 的「能碰 / 不能碰 / 怎么测」；手册 §2 真源清单、§3 项目硬规矩、§9 第一批队列；advisor 的「用户判断标准」先写三五条，之后每次用户拍板就补一条。
5. **接通知 hook**（可选，全局一次，所有总控项目共用）：按 `references/notify.md` 把 `scripts/notify.sh` 挂到 `~/.claude/settings.json` 的 Notification 事件。改全局设置前告诉用户改了什么。
6. **提交骨架**，并告诉用户：`.claude/agents/` 新建后要**新开会话**才会被 Agent 工具识别。

## 模式 B：运行（每轮循环）

**开场 / 压缩后第一件事**：读手册 §8 看板、`git status`、`git log -5`，核对看板上「进行中」的子代理是否还在跑。

1. **派工**：从 §9 队列取一项 → 按手册 §5 模板写提示词存 `docs/prompts/<序号>-给<工人>-<题目>.md` → 主目录必须已 commit（worktree 从 HEAD 分出）→ `Agent`（`subagent_type: worker-<槽>`，`isolation: "worktree"`，后台跑）→ 看板加一行（worktree、分支、基点 commit、日志字母）。
2. **交回**：派 `reviewer`（只读，按 §6 清单）。
   - 过 → `git merge --no-ff <worktree 分支>` → 跑合并后该跑的测试 → commit → push → 台账 / 看板 → 通知【完成】【剩余】。
   - 打回 → `SendMessage` **原工人**续做（新派的工人进不去别人的 worktree）；**第二次仍不过就停，报用户**。
3. **判断**：不在硬停清单 → 问 `advisor` 一句 → 按结论做 → 台账记一行「advisor 定 · 用户已看 = 否 · 怎么撤」。在硬停清单 → 通知【要你拍板】（事 / 推荐 / 回 A 或 B），**不等回复，先做别的**。
4. **预算**：每个工人任务写明命令上限与 token 预算；到 80% 让它收尾交活，日志写「未完成部分」。逐条处理数据的活要求「写脚本一次跑」。
5. **长会话**：先 commit + push、把每个工人停点写进看板，再通知【要你做】输入 `/compact`。

## 通知格式

`bash scripts/notify.sh --text "…"`（超 15 行截断）/ `--raw "…"`（整段，用于用户要的长清单或要复制的提示词）/ 加 `--dry-run` 只打印不发送。每条：
- 【完成】做完了什么（commit 号）
- 【要你拍板】/【要你做】只在需要时写，每条一行，带推荐和回复方式
- 【剩余】还剩什么

## 必守的几条（原因见 `references/lessons.md`）

- 只有总控 commit / push；工人不 commit、不 merge、不 `git checkout` / `restore` / `reset`。
- 审查员与工人必须是不同代理；工人不许为了变绿放宽断言。
- 「完成」分清：已实现 / 已测试 / 已合并 / 已部署 / 线上已验证。
- 同一目录同一时间一个工人；编译、模拟器、容器这类重活经 `tools/build-slot.sh` 排队。
- 测试输出重定向到日志文件，只读汇总，不把整份日志读进上下文。
- 线上数据库默认只读事务；部署只部署已合并的 commit，部署前备份、比对、写回滚。
- 密钥不进仓库、不进日志、不进提示词、不进通知。
- 台账只增不改口径；推翻已拍板的事属于硬停。

## 文件

- `templates/AUTOPILOT.md` 手册模板（§1 三档与硬停、§2 真源、§3 硬规矩、§4 角色与模型、§5 提示词模板、§6 审查清单、§7 台账、§8 看板、§9 队列）
- `templates/agents/` 审查员、顾问、工人三种代理模板
- `templates/compact.md` CLAUDE.md 的压缩保留段
- `scripts/init.sh` 生成骨架（默认预演，`--apply` 写入，不覆盖）
- `scripts/notify.sh` 通知（飞书 / Slack / Discord / 企业微信；手动 `--text` / `--raw`；hook 模式按 cwd 自动识别总控项目）
- `scripts/build-slot.sh` 重活排队器
- `references/lessons.md` 踩过的坑与对策
- `references/notify.md` 通知 hook 与定时摘要的接法
