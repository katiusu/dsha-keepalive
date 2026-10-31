#!/system/bin/sh
# dsha_keepalive - post-fs-data：尽早把基础结构建好并尝试拉起 app
# 注意：此阶段 am/pm 可能尚未就绪，凡是阻塞动作都放到后台子 shell，绝拖慢开机

MODDIR=${0%/*}
[ -f "$MODDIR/config.sh" ] && . "$MODDIR/config.sh"
BASE=${BASE:-/data/local/DshaKeepalive}
PKG=${PKG:-dsh.android.client}
COMPONENT=${COMPONENT:-dsh.android.client/com.deepseekharness.app.ui.MainActivity}
LOG=$BASE/Logs/keepalive.log

mkdir -p "$BASE/Logs" 2>/dev/null
: >"$LOG" 2>/dev/null
date +%s >"$BASE/.boot_ts" 2>/dev/null
echo 1 >"$BASE/.daemon_mode" 2>/dev/null

echo "[$(date '+%Y-%m-%d %H:%M:%S')] [post-fs-data] start, pkg=$PKG" >>"$LOG"

# 后台等包管理器就绪后再 start，最多等 240s；不阻塞 boot
(
    i=0
    while [ "$i" -lt 240 ]; do
        if [ -n "$(pm path "$PKG" 2>/dev/null)" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [post-fs-data] pm ready after ${i}s" >>"$LOG"
            break
        fi
        sleep 1
        i=$((i + 1))
    done
    if [ -z "$(pidof "$PKG" 2>/dev/null)" ]; then
        am start -n "$COMPONENT" >/dev/null 2>&1 &&
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [post-fs-data] early am start issued" >>"$LOG"
    fi
) &

exit 0
