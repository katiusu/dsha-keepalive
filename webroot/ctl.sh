#!/system/bin/sh
# dsha_keepalive - WebUI/终端共用控制后端
# 用法：ctl.sh status|start|stop|pause|resume|restart|verify|expert|log [n]|set KEY VALUE

WEBROOT=${0%/*}
MODDIR=$WEBROOT/..
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
status)
    out=$(sh "$0" __status_raw 2>/dev/null)
    printf '%s\n' "$out"
    printf '%s\n' "$out" >"$WEBROOT/status.txt" 2>/dev/null
    exit 0
    ;;
__status_raw)
    printf 'pkg=%s\n' "$PKG"
    printf 'daemon_pid=%s\n' "$([ -f "$PIDFILE" ] && cat "$PIDFILE")"
    alive && printf 'daemon=up\n' || printf 'daemon=down\n'
    [ -f "$BASE/.paused" ] && printf 'paused=yes\n' || printf 'paused=no\n'
    printf 'enabled=%s\n' "${ENABLED:-1}"

    app_pid=$(pidof "$PKG" 2>/dev/null | cut -d' ' -f1)
    if [ -n "$app_pid" ]; then
        printf 'app=up\napp_pid=%s\n' "$app_pid"
        printf 'oom=%s\n' "$(cat "/proc/$app_pid/oom_score_adj" 2>/dev/null)"
        printf 'cgroup=%s\n' "$(head -n1 "/proc/$app_pid/cgroup" 2>/dev/null | cut -d: -f3)"
    else
        printf 'app=down\napp_pid=\noom=\ncgroup=\n'
    fi

    printf 'proot_pid=%s\n' "$(pidof libproot.so 2>/dev/null | cut -d' ' -f1)"
    printf 'fgs=%s\n' "$(dumpsys activity services "$PKG" 2>/dev/null | grep -c 'isForeground=true')"
    ph=$(device_config get activity_manager max_phantom_processes 2>/dev/null)
    [ -n "$ph" ] || ph=$(dumpsys activity 2>/dev/null | grep -m1 'max_phantom_processes=' | cut -d= -f2)
    printf 'phantom=%s\n' "$ph"
    printf 'doze=%s\n' "$(dumpsys deviceidle whitelist 2>/dev/null | grep -c dsh)"
    printf 'standby=%s\n' "$(am get-standby-bucket "$PKG" 2>/dev/null)"
    printf 'restarts=%s\n' "$(grep '^restarts=' "$BASE/state" 2>/dev/null | cut -d= -f2)"
    printf 'uptime_s=%s\n' "$(grep '^uptime_s=' "$BASE/state" 2>/dev/null | cut -d= -f2)"
    printf 'interval=%s\n' "${INTERVAL:-20}"
    printf 'oom_adj_cfg=%s\n' "${OOM_ADJ:--1000}"
    printf 'force_fgs=%s\n' "${FORCE_FGS:-1}"
    printf 'phantom_limit_off=%s\n' "${DISABLE_PHANTOM_LIMIT:-1}"
    printf 'migrate=%s\n' "${MIGRATE_UID_CGROUP:-0}"
    printf 'launch=disabled\n'
    printf 'ver_module=%s\n' "$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -n1)"
    printf 'ver_daemon=%s\n' "$(grep '^ver=' "$BASE/state" 2>/dev/null | cut -d= -f2)"
    exit 0
    ;;
start)
    alive && {
        printf 'already running\n'
        exit 0
    }
    setsid sh "$MODDIR/keepalived.sh" >/dev/null 2>&1 &
    echo $! >"$PIDFILE"
    sleep 2
    printf 'started pid=%s\n' "$(cat "$PIDFILE")"
    ;;
reload)
    # 模块升级后旧进程仍跑旧代码，必须换掉
    if alive; then kill "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; fi
    rm -f "$PIDFILE"
    sleep 1
    setsid sh "$MODDIR/keepalived.sh" >/dev/null 2>&1 &
    echo $! >"$PIDFILE"
    sleep 2
    printf 'reloaded pid=%s\n' "$(cat "$PIDFILE")"
    ;;
stop)
    if alive; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        rm -f "$PIDFILE"
        printf 'stopped\n'
    else
        printf 'not running\n'
    fi
    ;;
pause)
    mkdir -p "$BASE"
    date '+%F %T paused via ctl' >"$BASE/.paused"
    printf 'paused\n'
    ;;
resume)
    rm -f "$BASE/.paused"
    printf 'resumed\n'
    ;;
restart)
    sh "$0" stop >/dev/null
    sleep 1
    sh "$0" start
    ;;
verify)
    printf 'oom=%s\n' "$(cat "/proc/$(pidof "$PKG" 2>/dev/null | cut -d' ' -f1)/oom_score_adj" 2>/dev/null)"
    ph=$(device_config get activity_manager max_phantom_processes 2>/dev/null)
    [ -n "$ph" ] || ph=$(dumpsys activity 2>/dev/null | grep -m1 'max_phantom_processes=' | cut -d= -f2)
    printf 'phantom=%s\n' "$ph"
    printf 'fgs=%s\n' "$(dumpsys activity services "$PKG" 2>/dev/null | grep -c 'isForeground=true')"
    printf 'doze=%s\n' "$(dumpsys deviceidle whitelist 2>/dev/null | grep -c dsh)"
    printf 'standby=%s\n' "$(am get-standby-bucket "$PKG" 2>/dev/null)"
    ;;
expert)
    n=0
    for p in $(pidof "$PKG" 2>/dev/null) $(pidof libproot.so 2>/dev/null); do
        printf '%s' "$p" >/sys/fs/cgroup/uid_0/cgroup.procs 2>/dev/null && {
            printf 'migrated %s\n' "$p"
            n=$((n + 1))
        }
    done
    printf 'done migrated=%s\n' "$n"
    ;;
log)
    tail -n "${2:-40}" "$BASE/Logs/keepalive.log" 2>/dev/null || printf '(无日志)\n'
    ;;
set)
    key=$2
    val=$3
    case "$key" in
    INTERVAL | OOM_ADJ | FORCE_FGS | DISABLE_PHANTOM_LIMIT | ENABLED | UNFREEZE_CGROUP | MIGRATE_UID_CGROUP | FGS_COOLDOWN | OPT_LOGCAT | DAEMON_MODE | OPT_DISABLE_DOZE) ;;
    *)
        printf 'refused unknown key: %s\n' "$key"
        exit 1
        ;;
    esac
    case "$val" in
    '' | *[!0-9-]*)
        printf 'refused bad value: %s\n' "$val"
        exit 1
        ;;
    esac
    sed -i "s|^$key=.*|$key=$val|" "$MODDIR/config.sh" 2>/dev/null || {
        printf 'write failed\n'
        exit 1
    }
    printf 'set %s=%s (重启守护生效: ctl.sh restart)\n' "$key" "$val"
    ;;
*)
    printf 'usage: ctl.sh status|start|stop|pause|resume|restart|verify|expert|log [n]|set KEY VALUE\n'
    ;;
esac
