#!/bin/bash
# 重活排队器：全机同一时刻最多 SLOTS 个（默认 2）重活在跑（编译、模拟器、容器、大批量测试）。
# 限 agent 数量太保守；agent 改代码几乎不占资源，吃资源的是这些重活，限它们就够了。
#
# 用法：
#   bash tools/build-slot.sh -- <命令…>
#   bash tools/build-slot.sh --sim <模拟器 UDID> -- <命令…>   # 结束后自动 simctl shutdown 那台
#   bash tools/build-slot.sh --status                          # 看谁占着
# 排队最多等 WAIT_MAX 秒（默认 540，留在 agent 单条命令 10 分钟超时内）；等不到退出码 75，稍后前台重试。
# 名额是文件锁（flock），进程死了锁自动释放。
SLOTS="${SLOTS:-2}"
WAIT_MAX="${WAIT_MAX:-540}"
LOCKDIR="${BUILD_SLOT_DIR:-/tmp/autopilot-build-slots}"
mkdir -p "$LOCKDIR"

if [ "${1:-}" = "--status" ]; then
  for f in "$LOCKDIR"/slot*.who; do [ -f "$f" ] && echo "$(basename "$f" .who): $(cat "$f")"; done
  exit 0
fi
SIM=""
if [ "${1:-}" = "--sim" ]; then SIM="$2"; shift 2; fi
[ "${1:-}" = "--" ] && shift
[ $# -eq 0 ] && { echo "用法见文件头"; exit 64; }

PY3="$(command -v python3)" || { echo "需要 python3"; exit 1; }
exec "$PY3" - "$LOCKDIR" "$SLOTS" "$WAIT_MAX" "$SIM" "$@" <<'PY'
import fcntl, os, subprocess, sys, time
lockdir, slots, wait_max, sim = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
cmd = sys.argv[5:]
deadline = time.time() + wait_max
held = None
while held is None:
    for i in range(slots):
        fd = os.open(os.path.join(lockdir, f"slot{i}.lock"), os.O_CREAT | os.O_RDWR)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            held = (i, fd); break
        except BlockingIOError:
            os.close(fd)
    if held is None:
        if time.time() > deadline:
            print(f"[build-slot] 名额满（{slots} 个都在用），等了 {wait_max}s；稍后在前台重试", flush=True)
            sys.exit(75)
        time.sleep(10)
i, fd = held
who = os.path.join(lockdir, f"slot{i}.who")
open(who, "w").write(f"pid={os.getpid()} cwd={os.getcwd()} since={time.strftime('%H:%M:%S')} cmd={' '.join(cmd)[:160]}")
print(f"[build-slot] 拿到名额 slot{i}", flush=True)
rc = 1
try:
    rc = subprocess.call(cmd)
finally:
    if sim:
        subprocess.call(["xcrun", "simctl", "shutdown", sim], stderr=subprocess.DEVNULL)
    try: os.remove(who)
    except FileNotFoundError: pass
    fcntl.flock(fd, fcntl.LOCK_UN); os.close(fd)
sys.exit(rc)
PY
