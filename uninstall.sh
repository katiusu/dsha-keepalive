#!/system/bin/sh
# 卸载：停 daemon、恢复系统策略、清日志
BASE=/data/local/DshaKeepalive
PKG=dsh.android.client

if [ -f "$BASE/keepalived.pid" ]; then
    kill "$(cat "$BASE/keepalived.pid")" 2>/dev/null
    rm -f "$BASE/keepalived.pid"
fi
pkill -f keepalived.sh 2>/dev/null

for op in RUN_IN_BACKGROUND RUN_ANY_IN_BACKGROUND START_FOREGROUND WAKE_LOCK; do
    cmd appops set "$PKG" "$op" default >/dev/null 2>&1
done
dumpsys deviceidle whitelist "-$PKG" >/dev/null 2>&1
rm -rf "$BASE"
