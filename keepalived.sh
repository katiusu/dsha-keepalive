#!/system/bin/sh
# dsha_keepalive v3 - keepalived：常驻 root 守护进程
# 四道防线：phantom 限制解除 / 前台服务保持 / 进程 oom 锁 / 系统策略白名单
# 用法：keepalived.sh [--once]

MODDIR=${0%/*}
[ -f "$MODDIR/config.sh" ] && . "$MODDIR/config.sh"
BASE=${BASE:-/data/local/DshaKeepalive}
PKG=${PKG:-dsh.android.client}
COMPONENT=${COMPONENT:-dsh.android.client/com.deepseekharness.app.ui.MainActivity}
SERVICE=${SERVICE:-dsh.android.client/com.deepseekharness.app.HarnessService}
SERVICE_ACTION=${SERVICE_ACTION:-com.deepseekharness.app.PREPARE_WEB_START}
INTERVAL=${INTERVAL:-20}
OOM_ADJ=${OOM_ADJ:--1000}
OPT_LOGCAT=${OPT_LOGCAT:-1}
DISABLE_PHANTOM_LIMIT=${DISABLE_PHANTOM_LIMIT:-1}
FORCE_FGS=${FORCE_FGS:-1}
FGS_COOLDOWN=${FGS_COOLDOWN:-600}
UNFREEZE_CGROUP=${UNFREEZE_CGROUP:-1}
MIGRATE_UID_CGROUP=${MIGRATE_UID_CGROUP:-0}
OPT_DISABLE_DOZE=${OPT_DISABLE_DOZE:-0}
RESTART_COOLDOWN=${RESTART_COOLDOWN:-45}
START_ON_BOOT=${START_ON_BOOT:-0}

VERSION=$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -n1)
VERSION=${VERSION:-unknown}
LOG=$BASE/Logs/keepalive.log
STATE=$BASE/state
PAUSED=$BASE/.paused
mkdir -p "$BASE/Logs" 2>/dev/null

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [keepalived] $*" >>"$LOG"; }
run() { "$@" >/dev/null 2>&1; }

rotate() {
    [ -f "$LOG" ] || return 0
    sz=$(wc -c <"$LOG" 2>/dev/null || echo 0)
    [ "$sz" -gt 524288 ] && mv -f "$LOG" "$LOG.old"
    return 0
}

# 主进程 pid：argv[0] 必须精确等于包名
# 关键：不能用 cmdline 子串匹配，否则 "$PKG:shizuku" 子进程会被当成 app 还活着
argv0() { tr '\0' '\n' <"/proc/$1/cmdline" 2>/dev/null | head -n1; }

main_pid() {
    for p in $(pidof "$PKG" 2>/dev/null); do
        [ "$(argv0 "$p")" = "$PKG" ] && { echo "$p"; return 0; }
    done
    for d in /proc/[0-9]*; do
        p=${d#/proc/}
        [ "$p" = "$$" ] && continue
        [ "$(argv0 "$p")" = "$PKG" ] && { echo "$p"; return 0; }
    done
    return 1
}

# 要保护但不算 app 存活的附属进程：proot 容器 + :shizuku 子进程
aux_pids() {
    out=""
    for p in $(pidof libproot.so 2>/dev/null); do out="$out $p"; done
    for p in $(pidof "$PKG" 2>/dev/null); do
        [ "$(argv0 "$p")" = "$PKG" ] || out="$out $p"
    done
    echo "$out"
}

find_pids() {
    out=$(main_pid)
    a=$(aux_pids)
    [ -n "$a" ] && out="$out $a"
    echo "$out" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' '
}

app_uid() {
    pid=$(pidof "$PKG" 2>/dev/null | cut -d' ' -f1)
    [ -n "$pid" ] || return 1
    set -- $(grep '^Uid:' "/proc/$pid/status" 2>/dev/null)
    [ -n "$2" ] && echo "$2"
}

# 防线 1：解除 phantom process 限制（默认 32，超了 AM 会周期性 trim）
disable_phantom() {
    [ "$DISABLE_PHANTOM_LIMIT" = "1" ] || return 0
    cur=$(dumpsys activity 2>/dev/null | grep -m1 "max_phantom_processes=")
    case "$cur" in
        *2147483647*) return 0 ;;
    esac
    run device_config put activity_manager max_phantom_processes 2147483647
    run settings put global settings_enable_monitor_phantom_procs false
    log "phantom limit cleared (was: ${cur#*=})"
}

# 防线 2：保证前台服务（cached 状态才会被 AM trim）
FGS_LAST=0
ensure_fgs() {
    [ "$FORCE_FGS" = "1" ] || return 0
    out=$(dumpsys activity services "$PKG" 2>/dev/null)
    case "$out" in
        *"isForeground=true"*) return 0 ;;
        *HarnessService*) ;; # 服务在跑但没进前台 -> 需要拉起
        *) return 0 ;;       # 服务都不在，交给 restart 逻辑
    esac
    now=$(date +%s)
    [ $((now - FGS_LAST)) -lt "$FGS_COOLDOWN" ] && return 0
    FGS_LAST=$now
    log "FGS not active -> am start-foreground-service"
    run am start-foreground-service -n "$SERVICE" -a "$SERVICE_ACTION"
}

# 防线 3：进程 oom 锁 + cgroup 解冻
protect_procs() {
    for p in $1; do
        [ -d "/proc/$p" ] || continue
        cur=$(cat "/proc/$p/oom_score_adj" 2>/dev/null)
        [ "$cur" = "$OOM_ADJ" ] || echo "$OOM_ADJ" >"/proc/$p/oom_score_adj" 2>/dev/null
    done
    [ "$UNFREEZE_CGROUP" = "1" ] || return 0
    uid=$(app_uid)
    [ -n "$uid" ] || return 0
    for f in /sys/fs/cgroup/uid_"$uid"/cgroup.freeze /sys/fs/cgroup/uid_"$uid"/pid_*/cgroup.freeze; do
        [ -e "$f" ] || continue
        [ "$(cat "$f" 2>/dev/null)" = "0" ] || echo 0 >"$f" 2>/dev/null
    done
}

# 极硬模式：把 app 进程迁出 uid cgroup（AM 的 killProcessGroup / force-stop 打不到）
migrate_cgroup() {
    [ "$MIGRATE_UID_CGROUP" = "1" ] || return 0
    for p in $1; do
        [ -d "/proc/$p" ] || continue
        cur=$(cat "/proc/$p/cgroup" 2>/dev/null)
        case "$cur" in
            *uid_0*) continue ;;
        esac
        printf '%s' "$p" >/sys/fs/cgroup/uid_0/cgroup.procs 2>/dev/null &&
            log "migrated pid $p -> uid_0 cgroup"
    done
}

# 防线 4：系统层白名单
apply_policy() {
    run cmd appops set "$PKG" RUN_IN_BACKGROUND allow
    run cmd appops set "$PKG" RUN_ANY_IN_BACKGROUND allow
    run cmd appops set "$PKG" START_FOREGROUND allow
    run cmd appops set "$PKG" BOOT_COMPLETED allow
    run cmd appops set "$PKG" WAKE_LOCK allow
    run dumpsys deviceidle whitelist "+$PKG"
    run am set-standby-bucket "$PKG" active
    run cmd power set-adaptive-power-saver-enabled false
    [ "$OPT_DISABLE_DOZE" = "1" ] && run dumpsys deviceidle disable
    log "policy applied"
}

restart_app() {
    log "target down -> am start $COMPONENT"
    run am start -n "$COMPONENT"
    sleep 8
    if [ -z "$(pidof "$PKG" 2>/dev/null)" ]; then
        log "am start failed -> monkey fallback"
        run monkey -p "$PKG" -c android.intent.category.LAUNCHER 1
    fi
    sleep "$RESTART_COOLDOWN"
    apply_policy
}

write_state() {
    alive="down"
    mpid=$(main_pid)
    [ -n "$mpid" ] && alive="up"
    boot_ts=$(cat "$BASE/.boot_ts" 2>/dev/null || echo 0)
    now=$(date +%s)
    up=$((now - boot_ts))
    fgs="no"
    dumpsys activity services "$PKG" 2>/dev/null | grep -q "isForeground=true" && fgs="yes"
    ph=$(dumpsys activity 2>/dev/null | grep -m1 "max_phantom_processes=")
    cat >"$STATE" <<EOF
pkg=$PKG
ver=$VERSION
ts=$now
uptime_s=$up
app=$alive
app_pid=$mpid
fgs=$fgs
pids=$(find_pids)
restarts=$RESTARTS
paused=$( [ -f "$PAUSED" ] && echo yes || echo no )
phantom=${ph#*=}
interval=$INTERVAL
pid=$KEEPALIVED_PID
EOF
}

start_logcat() {
    [ "$OPT_LOGCAT" = "1" ] || return 0
    logcat -b main,system,events -v time 2>/dev/null |
        grep -iE "dsh|lmkd|lowmemorykiller|am_kill|am_proc_died|powerkeeper|anr|force-stop" \
            >>"$BASE/Logs/app.log" 2>/dev/null &
    LOGCAT_PID=$!
    log "logcat collector PID $LOGCAT_PID"
}

stop_logcat() { [ -n "$LOGCAT_PID" ] && kill "$LOGCAT_PID" 2>/dev/null; }
cleanup() {
    stop_logcat
    log "keepalived exiting"
    exit 0
}
trap cleanup INT TERM HUP

ONCE=0
[ "$1" = "--once" ] && ONCE=1

rotate
KEEPALIVED_PID=$$
echo "$KEEPALIVED_PID" >"$BASE/keepalived.pid" 2>/dev/null
echo "$OOM_ADJ" >/proc/$$/oom_score_adj 2>/dev/null
log "=== keepalived v3 start (pid=$KEEPALIVED_PID pkg=$PKG interval=${INTERVAL}s oom=$OOM_ADJ once=$ONCE) ==="

RESTARTS=0
disable_phantom
apply_policy
pids=$(find_pids)
[ -n "$pids" ] && { protect_procs "$pids"; migrate_cgroup "$pids"; }
ensure_fgs
[ "$ONCE" = "0" ] && start_logcat

tick=0
while true; do
    # 用户暂停防护（action.sh pause）：一律不拉起、不锁、不刷策略
    if [ -f "$PAUSED" ]; then
        write_state
        sleep "$INTERVAL"
        continue
    fi
    pids=$(main_pid)
    if [ -n "$pids" ]; then
        : >"$BASE/.seen"    # 只要见过 app 一次，之后它被杀才拉起
        pids=$(find_pids)
        protect_procs "$pids"
        migrate_cgroup "$pids"
        ensure_fgs
    else
        # START_ON_BOOT=0：开机后用户没自己打开过 app 就不拉起（不主动开机自启）
        if [ "$START_ON_BOOT" = "1" ] || [ -f "$BASE/.seen" ]; then
            log "app not running (main pid missing), restarting"
            if [ "$RESTARTS" -ge 5 ]; then
                log "restart fuse blown ($RESTARTS), backing off 600s"
                sleep 600
                RESTARTS=0
            fi
            restart_app
            RESTARTS=$((RESTARTS + 1))
        fi
    fi
    tick=$((tick + 1))
    # 每 10 分钟重刷系统策略（厂商 powerkeeper 会自愈）
    [ $((tick % 30)) -eq 0 ] && {
        apply_policy
        disable_phantom
    }
    [ $((tick % 3)) -eq 0 ] && sh "$MODDIR/webroot/ctl.sh" status >/dev/null 2>&1 &
    write_state
    [ "$ONCE" = "1" ] && {
        log "one-shot done"
        cleanup
    }
    sleep "$INTERVAL"
done
