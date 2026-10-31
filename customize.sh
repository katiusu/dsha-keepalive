#!/system/bin/sh
# KernelSU / ReSukiSU 安装钩子
ui_print "- DSHA 保活模块 (Daemon & Keep-Alive) 安装中"
ui_print "- 目标: dsh.android.client + libproot.so 容器*"

mkdir -p /data/local/DshaKeepalive/Logs
set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in service.sh action.sh uninstall.sh customize.sh keepalived.sh post-fs-data.sh webroot/ctl.sh; do
    set_perm "$MODPATH/$f" 0 0 0755
done
set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
set_perm_recursive /data/local/DshaKeepalive 0 0 0755 0644

ui_print "- 完成。重启后 daemon 自动运行。"
ui_print "- 管理器模块页点「WebUI」打开图形界面。"
