#!/system/bin/sh
# KernelSU / ReSukiSU 安装钩子
ui_print "- DSHA 保活模块 (Daemon & Keep-Alive) 安装中"
ui_print "- 目标: dsh.android.client + libproot.so 容器*"

mkdir -p /data/local/DshaKeepalive/Logs
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
for f in service.sh action.sh uninstall.sh customize.sh keepalived.sh post-fs-data.sh webroot/ctl.sh; do
    set_perm "$MODPATH/$f" 0 0 0755
done

# 升级时结束还在跑旧代码的守护（否则新脚本永远不会被执行）
for d in /proc/[0-9]*; do
    [ -r "$d/cmdline" ] || continue
    if tr '\000' ' ' <"$d/cmdline" 2>/dev/null | grep -q "dsha_keepalive/keepalived.sh"; then
        kill "${d#/proc/}" 2>/dev/null
        ui_print "- 已结束旧守护进程 ${d#/proc/}"
    fi
done
rm -f /data/local/DshaKeepalive/keepalived.pid
set_perm_recursive /data/local/DshaKeepalive 0 0 0755 0644

ui_print "- 完成。重启后 daemon 自动运行。"
ui_print "- 管理器模块页点「WebUI」打开图形界面。"
