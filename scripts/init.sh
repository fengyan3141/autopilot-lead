#!/bin/bash
# 给一个项目生成总控骨架。默认只预演，加 --apply 才写入；已存在的文件一律跳过，不覆盖。
#
#   bash init.sh --project-dir <绝对路径> --slug <英文简称> --name <显示名> \
#     --branch <主干分支> --slots "app:ios/,server:supabase/" [--apply]
#
# 生成：docs/AUTOPILOT.md、docs/prompts/、.claude/agents/{reviewer,advisor,worker-<槽>}.md、
#       .claude/autopilot.env、tools/build-slot.sh、CLAUDE.md 的 Compact Instructions 段、.gitignore 的 /build-*/
set -eu
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PY3="$(command -v python3)" || { echo "需要 python3"; exit 1; }
exec "$PY3" - "$SKILL_DIR" "$@" <<'PY'
import argparse, datetime, os, shutil, stat, sys
skill = sys.argv[1]
ap = argparse.ArgumentParser(prog="init.sh")
ap.add_argument("--project-dir", required=True)
ap.add_argument("--slug", required=True)
ap.add_argument("--name", required=True)
ap.add_argument("--branch", required=True)
ap.add_argument("--slots", required=True, help='例："app:ios/,server:supabase/"')
ap.add_argument("--notify", default="feishu", choices=["feishu", "slack", "discord", "wecom", "none"])
ap.add_argument("--tz", default="", help="时区，如 Asia/Shanghai；不给就读本机")
ap.add_argument("--apply", action="store_true")
a = ap.parse_args(sys.argv[2:])

root = os.path.abspath(a.project_dir)
if not os.path.isdir(os.path.join(root, ".git")) and not os.path.isfile(os.path.join(root, ".git")):
    sys.exit(f"不是 git 仓库：{root}")
slots = []
for part in a.slots.split(","):
    part = part.strip()
    if not part: continue
    if ":" not in part: sys.exit(f"槽位格式应为 名称:目录，收到 {part!r}")
    n, scope = part.split(":", 1)
    slots.append((n.strip(), scope.strip()))
if not slots: sys.exit("至少要一个槽位")

today = datetime.date.today().isoformat()
tz = a.tz or os.environ.get("TZ", "")
if not tz:
    try:
        link = os.path.realpath("/etc/localtime")
        tz = link.split("zoneinfo/", 1)[1] if "zoneinfo/" in link else "UTC"
    except OSError:
        tz = "UTC"
def fill(text, **extra):
    m = {"NAME": a.name, "SLUG": a.slug, "BRANCH": a.branch, "DATE": today, "TZ": tz, **extra}
    for k, v in m.items(): text = text.replace("{{%s}}" % k, v)
    return text
def tpl(rel): return open(os.path.join(skill, "templates", rel), encoding="utf-8").read()

queues = "\n\n".join(f"### {n} 槽（worker-{n}，同一时间一个；能碰 `{s}`）\n1. …" for n, s in slots)
plan = [
    ("docs/AUTOPILOT.md", fill(tpl("AUTOPILOT.md"), SLOT_QUEUES=queues), False),
    ("docs/prompts/.gitkeep", "", False),
    (".claude/agents/reviewer.md", fill(tpl("agents/reviewer.md")), False),
    (".claude/agents/advisor.md", fill(tpl("agents/advisor.md")), False),
    (".claude/autopilot.env", f'AUTOPILOT_SLUG="{a.slug}"\nAUTOPILOT_NAME="{a.name}"\nAUTOPILOT_NOTIFY="{a.notify}"\n', False),
    ("tools/build-slot.sh", open(os.path.join(skill, "scripts/build-slot.sh"), encoding="utf-8").read(), True),
]
for n, s in slots:
    plan.append((f".claude/agents/worker-{n}.md", fill(tpl("agents/worker.md"), SLOT=n, SCOPE=s), False))

mode = "写入" if a.apply else "预演"
print(f"[{mode}] 项目 {root}")
for rel, content, exe in plan:
    p = os.path.join(root, rel)
    if os.path.exists(p):
        print(f"  跳过（已存在）{rel}"); continue
    print(f"  新建 {rel}")
    if a.apply:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "w", encoding="utf-8").write(content)
        if exe: os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

# CLAUDE.md：只追加，不改原有内容
cm = os.path.join(root, "CLAUDE.md")
snippet = tpl("compact.md")
if os.path.exists(cm) and "Compact Instructions" in open(cm, encoding="utf-8").read():
    print("  跳过 CLAUDE.md（已有 Compact Instructions）")
else:
    print(("  追加" if os.path.exists(cm) else "  新建") + " CLAUDE.md 的 Compact Instructions 段")
    if a.apply:
        with open(cm, "a", encoding="utf-8") as f:
            if not os.path.exists(cm) or os.path.getsize(cm) == 0: f.write(f"# CLAUDE.md\n\n总控手册：docs/AUTOPILOT.md\n")
            f.write(snippet)

gi = os.path.join(root, ".gitignore")
existing = open(gi, encoding="utf-8").read() if os.path.exists(gi) else ""
if "/build-*/" in existing.splitlines():
    print("  跳过 .gitignore（已有 /build-*/）")
else:
    print("  追加 .gitignore：/build-*/（工人测试日志目录）")
    if a.apply:
        with open(gi, "a", encoding="utf-8") as f:
            if existing and not existing.endswith("\n"): f.write("\n")
            f.write("/build-*/\n")

hook = os.path.expanduser(f"~/.claude/autopilot/webhooks/{a.slug}")
print()
print("接下来：")
if a.notify == "none":
    print("  1. 通知已关（--notify none），跳过 webhook")
else:
    print(f"  1. 用户自己把 {a.notify} 机器人 webhook 写进 {hook}（第一行；不要贴进对话）" + ("  ← 已存在" if os.path.exists(hook) else ""))
print("  2. 补 worker-<槽>.md 的能碰 / 不能碰 / 怎么测，AUTOPILOT §2 真源、§9 队列")
print("  3. 通知 hook 没接过的话，按 references/notify.md 接一次（全局共用）")
print("  4. commit 骨架；新开会话后 .claude/agents 才会被识别")
if not a.apply: print("\n（预演，没写任何文件；确认后加 --apply）")
PY
