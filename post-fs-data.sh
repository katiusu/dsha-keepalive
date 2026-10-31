#!/system/bin/sh
# dsha_keepalive - post-fs-data：只建基础结构，不主动拉起 app
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

# 开机不主动启动 app：清掉"见过 app"标记，等你手动打开后守护才启用拉起
rm -f "$BASE/.seen" 2>/dev/null
echo "[$(date '+%Y-%m-%d %H:%M:%S')] [post-fs-data] auto-start disabled, .seen cleared" >>"$LOG"

exit 0
