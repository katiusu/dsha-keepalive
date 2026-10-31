#!/system/bin/sh
# 模块页「执行」：action.sh [status|start|stop|restart|pause|resume|verify|expert]
MODDIR=${0%/*}
[ -f "$MODDIR/config.sh" ] && . "$MODDIR/config.sh"
BASE=${BASE:-/data/local/DshaKeepalive}
PKG=${PKG:-dsh.android.client}
PIDFILE=$BASE/keepalived.pid

alive() {
    [ -f "$PIDFILE" ] || return 1
    p=$(cat "$PIDFILE" 2>/dev/null)
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

case "$1" in
start)
    alive && echo "已在运行 (PID $(cat "$PIDFILE"))" && exit 0
    setsid sh "$MODDIR/keepalived.sh" >/dev/null 2>&1 &
    echo $! >"$PIDFILE"
    sleep 2
    echo "已启动 (PID $(cat "$PIDFILE"))"
    exit 0
    ;;
stop)
    alive && kill "$(cat "$PIDFILE")" 2>/dev/null && echo "已停止"
    rm -f "$PIDFILE"
    exit 0
    ;;
pause)
    # 暂停防护：daemon 继续跑但不拉起、不锁进程，你可以随便关 app/容器
    mkdir -p "$BASE"
    date '+%F %T  paused by action.sh' >"$BASE/.paused"
    echo "已暂停防护（action.sh resume 恢复；重启后不保留）"
    exit 0
    ;;
resume)
    rm -f "$BASE/.paused"
    echo "已恢复防护"
    exit 0
    ;;
restart)
    sh "$0" stop
    sleep 1
    sh "$0" start
    exit 0
    ;;
verify)
    echo "== 四道防线自检 =="
    printf '%-24s ' "oom_score_adj:"
    pid=$(pidof "$PKG" 2>/dev/null | cut -d' ' -f1)
    cat "/proc/$pid/oom_score_adj" 2>/dev/null || echo "app 未运行"
    printf '%-24s ' "max_phantom_processes:"
    dumpsys activity 2>/dev/null | grep -m1 "max_phantom_processes=" | cut -d= -f2
    printf '%-24s ' "FGS(isForeground):"
    dumpsys activity services "$PKG" 2>/dev/null | grep -m1 "isForeground" | tr -d ' '
    printf '%-24s ' "standby bucket:"
    cmd appops get "$PKG" RUN_IN_BACKGROUND 2>/dev/null | tail -n1
    printf '%-24s ' "doze whitelist:"
    dumpsys deviceidle whitelist 2>/dev/null | grep -c dsh
    printf '%-24s ' "cgroup:"
    cat "/proc/$pid/cgroup" 2>/dev/null | head -1
    exit 0
    ;;
expert)
    # 极硬模式：迁出 uid cgroup，AM 的 force-stop / killProcessGroup 打不到 app
    for p in $(pidof "$PKG" 2>/dev/null) $(pidof libproot.so 2>/dev/null); do
        printf '%s' "$p" >/sys/fs/cgroup/uid_0/cgroup.procs 2>/dev/null &&
            echo "pid $p -> uid_0"
    done
    echo "注意：此后系统「强行停止」对该 app 无效，重启后恢复"
    exit 0
    ;;
esac

echo "== Daemon =="
alive && echo "🟢 Running (PID $(cat "$PIDFILE"))" || echo "🔴 Not running"
if [ -f "$BASE/.paused" ]; then
    echo "⏸  防护已暂停（$(cat "$BASE/.paused")）——app 可被正常关闭，不会被拉起"
fi
echo
echo "== state =="
cat "$BASE/state" 2>/dev/null || echo "(无状态文件)"
echo
echo "== 最近日志 =="
tail -n 15 "$BASE/Logs/keepalive.log" 2>/dev/null || echo "(无日志)"
echo
echo "提示：action.sh verify 看四道防线；action.sh expert 进极硬模式"
