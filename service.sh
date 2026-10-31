#!/system/bin/sh
# dsha_keepalive v3 - late_start service：等开机 -> 起 keepalived -> 回写状态到 module.prop

MODDIR=${0%/*}
[ -f "$MODDIR/config.sh" ] && . "$MODDIR/config.sh"
BASE=${BASE:-/data/local/DshaKeepalive}
PKG=${PKG:-dsh.android.client}
DAEMON_MODE=${DAEMON_MODE:-1}
ENABLED=${ENABLED:-1}
LOG=$BASE/Logs/keepalive.log
PIDFILE=$BASE/keepalived.pid

mkdir -p "$BASE/Logs" 2>/dev/null
exec >>"$LOG" 2>&1

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [service] $*"; }

VERSION=$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -n1)
VERSIONCODE=$(sed -n 's/^versionCode=//p' "$MODDIR/module.prop" 2>/dev/null | head -n1)
VERSION=${VERSION:-v0.0.0}
VERSIONCODE=${VERSIONCODE:-0}

update_prop() {
    cat >"$MODDIR/module.prop" <<EOF
id=dsha_keepalive
name=DSHA: Daemon & Keep-Alive
version=$VERSION
versionCode=$VERSIONCODE
author=远方缘分的天空
description=$*
EOF
}

daemon_alive() {
    [ -f "$PIDFILE" ] || return 1
    p=$(cat "$PIDFILE" 2>/dev/null)
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}

# 版本变了或残留进程存在时，先结束旧守护，避免继续跑旧代码
for d in /proc/[0-9]*; do
    [ -r "$d/cmdline" ] || continue
    tr '\000' ' ' <"$d/cmdline" 2>/dev/null | grep -q "dsha_keepalive/keepalived.sh" || continue
    pid="${d#/proc/}"
    [ "$pid" = "$(cat "$PIDFILE" 2>/dev/null)" ] || continue
    kill "$pid" 2>/dev/null && log "killed stale keepalived pid=$pid"
done
rm -f "$PIDFILE"

log "service.sh start"

i=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
    sleep 1
    i=$((i + 1))
    [ "$i" -gt 600 ] && {
        log "boot_completed timeout"
        break
    }
done
log "boot completed"

if [ "$ENABLED" != "1" ]; then
    log "ENABLED=0, module disabled, not starting daemon"
    update_prop "已停用 (config.sh ENABLED=0)"
    exit 0
fi
if daemon_alive; then
    log "daemon already running (PID $(cat "$PIDFILE"))"
else
    if [ "$DAEMON_MODE" = "1" ]; then
        if command -v setsid >/dev/null 2>&1; then
            setsid sh "$MODDIR/keepalived.sh" >/dev/null 2>&1 &
        else
            sh "$MODDIR/keepalived.sh" >/dev/null 2>&1 &
        fi
        echo $! >"$PIDFILE"
        log "daemon launched, PID $(cat "$PIDFILE")"
        sleep 5
        daemon_alive || log "WARNING: daemon died right after launch"
    else
        log "DAEMON_MODE=0, one-shot only"
        sh "$MODDIR/keepalived.sh" --once >/dev/null 2>&1
    fi
fi

sleep 3
APP_PID=$(pidof "$PKG" 2>/dev/null)
DPID=$(cat "$PIDFILE" 2>/dev/null)
PH=$(dumpsys activity 2>/dev/null | grep -m1 "max_phantom_processes=" | cut -d= -f2)
DFG=🔴
[ "$(dumpsys activity services "$PKG" 2>/dev/null | grep -c 'isForeground=true')" -gt 0 ] && DFG=🟢

if daemon_alive; then
    update_prop "Daemon: 🟢 Running (PID ${DPID}) | App: $( [ -n "$APP_PID" ] && echo "🟢 ${APP_PID}" || echo '🔴 Down') | FGS: ${DFG} | Phantom: ${PH}"
else
    update_prop "Daemon: 🔴 Not Running | App: $( [ -n "$APP_PID" ] && echo "🟢 ${APP_PID}" || echo '🔴 Down')"
fi
log "module.prop updated"
