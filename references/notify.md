# 通知接法

支持飞书、Slack、Discord、企业微信的群机器人 webhook；不需要通知就在 `init.sh` 加 `--notify none`（事后改 `.claude/autopilot.env` 里的 `AUTOPILOT_NOTIFY` 也行）。

## 1. webhook（每个项目一次，用户自己做）
在对应平台的群里添加「自定义机器人 / Incoming Webhook」，复制 URL，然后用户自己执行（macOS 用 `pbpaste`，Linux 可换成 `xclip -o` 或直接用编辑器写入）：
```bash
mkdir -p ~/.claude/autopilot/webhooks
pbpaste > ~/.claude/autopilot/webhooks/<slug>
chmod 600 ~/.claude/autopilot/webhooks/<slug>
```
**webhook 等同密钥：不要贴进对话、不要进仓库。** 多个项目可以共用一个群，也可以各用各的。

## 2. 手动推（总控用）
```bash
bash <skill 目录>/scripts/notify.sh --text "【完成】…"     # 超 15 行截断
bash <skill 目录>/scripts/notify.sh --raw  "…"            # 整段不截断
bash <skill 目录>/scripts/notify.sh --dry-run --text "…"   # 只打印要发的 JSON，验证配置
```
在项目目录里运行即可（从当前目录往上找 `.claude/autopilot.env`）；不在项目目录就加 `--project-dir <路径>`。

## 3. hook（可选，全局一次，所有总控项目共用）
在 `~/.claude/settings.json` 的 `hooks.Notification` 里加一项（已有其他 Notification hook 就并列加，不要覆盖）。`<skill 目录>` 换成本 skill 的实际安装路径，例如 `~/.claude/skills/autopilot-lead`：
```json
{ "hooks": [ { "type": "command", "command": "bash <skill 目录>/scripts/notify.sh", "timeout": 15 } ] }
```
效果：总控卡在权限确认或停下等回复时，推一行【要你做】。不是总控项目（找不到 `.claude/autopilot.env`）的会话静默跳过。

## 4. 定时摘要（可选，确有需要再加）
用 cron / launchd 每天固定时间触发一次让总控写摘要。多数项目靠「每完成一件推一条」就够了，别一开始就加。
