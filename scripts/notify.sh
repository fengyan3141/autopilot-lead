#!/bin/bash
# 总控 → 群机器人通知（飞书 / Slack / Discord / 企业微信）。两种用法：
#   手动：notify.sh --text "正文"   （超 15 行截断）
#         notify.sh --raw  "正文"   （不截断：长清单、要复制的提示词）
#         可加 --project-dir <路径>；不给就从当前目录往上找 .claude/autopilot.env
#         加 --dry-run 只打印将要发送的 JSON，不发送
#   hook：挂在 ~/.claude/settings.json 的 Notification 事件，stdin 是 hook JSON；
#         只在 cwd 属于总控项目（往上能找到 .claude/autopilot.env）时推，其他项目静默退出。
#
# 项目配置 <项目>/.claude/autopilot.env：
#   AUTOPILOT_SLUG=<slug>  AUTOPILOT_NAME=<显示名>  AUTOPILOT_NOTIFY=feishu|slack|discord|wecom|none
# webhook：~/.claude/autopilot/webhooks/<slug> 第一行（不进仓库，用户自己写入）。
# 日志：~/.claude/autopilot/notify.log（时间、HTTP 码、正文首行）。
set -u
MAX_LINES=15
MODE="hook"; TEXT=""; PROJECT_DIR=""; DRY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --text) MODE="text"; TEXT="$2"; shift 2 ;;
    --raw)  MODE="raw";  TEXT="$2"; shift 2 ;;
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --dry-run) DRY=1; shift ;;
    *) shift ;;
  esac
done
PY3="$(command -v python3)" || { [ "$MODE" != "hook" ] && echo "需要 python3"; exit 0; }

find_env() {  # 从给定目录往上找 .claude/autopilot.env
  local d="$1"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/.claude/autopilot.env" ] && { echo "$d/.claude/autopilot.env"; return; }
    d=$(dirname "$d")
  done
}

if [ "$MODE" = "hook" ]; then
  IN=$(cat)
  CWD=$(printf '%s' "$IN" | "$PY3" -c 'import sys,json;print(json.load(sys.stdin).get("cwd",""))' 2>/dev/null)
  ENV_FILE=$(find_env "${CWD:-/}")
else
  ENV_FILE=$(find_env "${PROJECT_DIR:-$PWD}")
fi
[ -n "${ENV_FILE:-}" ] || { [ "$MODE" != "hook" ] && echo "不在总控项目里（找不到 .claude/autopilot.env）"; exit 0; }
# shellcheck disable=SC1090
. "$ENV_FILE"
SLUG="${AUTOPILOT_SLUG:-}"; NAME="${AUTOPILOT_NAME:-$SLUG}"; KIND="${AUTOPILOT_NOTIFY:-feishu}"
[ "$KIND" = "none" ] && exit 0

if [ "$MODE" = "hook" ]; then
  EVENT=$(printf '%s' "$IN" | "$PY3" -c 'import sys,json;d=json.load(sys.stdin);print(d.get("hook_event_name",""),"|",d.get("notification_type",""))' 2>/dev/null)
  case "$EVENT" in
    Notification*permission_prompt*) TEXT="【要你做】点允许：${NAME}总控卡在权限确认" ;;
    Notification*idle_prompt*)       TEXT="【要你做】回复：${NAME}总控停下来等你" ;;
    *) exit 0 ;;
  esac
elif [ "$MODE" = "text" ] && [ "$(printf '%s\n' "$TEXT" | wc -l | tr -d ' ')" -gt "$MAX_LINES" ]; then
  TEXT="$(printf '%s\n' "$TEXT" | head -n $((MAX_LINES - 1)))
（超长已截断，全文见 docs/AUTOPILOT.md §8）"
fi

BODY=$(printf '%s' "$TEXT" | "$PY3" -c '
import sys, json
kind, text = sys.argv[1], sys.stdin.read()
body = {
    "feishu":  {"msg_type": "text", "content": {"text": text}},
    "slack":   {"text": text},
    "discord": {"content": text[:2000]},
    "wecom":   {"msgtype": "text", "text": {"content": text}},
}.get(kind)
if body is None: sys.exit("未知的 AUTOPILOT_NOTIFY：" + kind)
print(json.dumps(body, ensure_ascii=False))' "$KIND") || exit 0

if [ "$DRY" = 1 ]; then echo "[dry-run] $KIND → $BODY"; exit 0; fi

HOOK_FILE="$HOME/.claude/autopilot/webhooks/$SLUG"
[ -n "$SLUG" ] && [ -r "$HOOK_FILE" ] || { [ "$MODE" != "hook" ] && echo "没有 webhook：$HOOK_FILE"; exit 0; }
URL=$(head -1 "$HOOK_FILE")
mkdir -p "$HOME/.claude/autopilot"
LOG="$HOME/.claude/autopilot/notify.log"
# 前台 + 超时：放后台会在调用方退出时被杀、也留不下痕迹
RESP=$(curl -sS -m 10 -w '\n%{http_code}' -H 'Content-Type: application/json' -d "$BODY" "$URL" 2>&1)
CODE=$(printf '%s' "$RESP" | tail -n1); RBODY=$(printf '%s' "$RESP" | sed '$d')
printf '%s\t%s\tHTTP %s\t%s\t%s\n' "$(date '+%F %T %Z')" "$SLUG" "$CODE" "$RBODY" "$(printf '%s' "$TEXT" | head -n1 | cut -c1-40)" >> "$LOG"
[ "$MODE" != "hook" ] && echo "HTTP $CODE $RBODY"
exit 0
