# dsha_keepalive 运行参数（v3）
# 0 = 模块整体停用（等同 pause），1 = 正常
ENABLED=1

PKG=dsh.android.client
COMPONENT=dsh.android.client/com.deepseekharness.app.ui.MainActivity
SERVICE=dsh.android.client/com.deepseekharness.app.HarnessService
SERVICE_ACTION=com.deepseekharness.app.PREPARE_WEB_START

INTERVAL=20          # 守护轮询间隔（秒）
OOM_ADJ=-1000        # 进程 oom_score_adj；-1000 = LMK/内核 OOM 免疫

DAEMON_MODE=1        # 1 = 常驻 daemon；0 = 只跑一次策略
OPT_LOGCAT=1         # 1 = 抓 logcat（lmkd/am_kill/powerkeeper/anr）到 Logs/app.log

# --- 关键防线 ---
# 1 = 解除 ActivityManager 的 phantom process 限制（本机 max_phantom_processes=32，
#     正是日志里 "Trimming phantom processes" 的来源，会连带杀掉容器里的 sh）
DISABLE_PHANTOM_LIMIT=1
# 1 = 观察 FGS 是否在前台（只记录到状态文件，不做任何拉起）
FORCE_FGS=1
# 保留字段（历史上用于 FGS 拉起冷却；现已无拉起路径，仅兼容旧配置）
FGS_COOLDOWN=600
# 1 = 持续把 app 的 cgroup 解冻（本机 use_freezer=false，仅作兜底）
UNFREEZE_CGROUP=1
# 1 = 极硬模式：把 app 进程迁出 uid_10227 cgroup 到 uid_0
#     效果：AM 的 killProcessGroup / am force-stop 打不到它
#     代价：系统"强行停止"、部分安全/统计逻辑会失准，默认关闭
MIGRATE_UID_CGROUP=0

OPT_DISABLE_DOZE=0   # 1 = 关整机 Doze（激进）
# 本模块没有任何拉起路径：不开 app、不起容器、不 monkey。
# 行为约定：app 不在时只写日志，等你自己打开 —— 任何模式（含极硬模式）都成立。
BASE=/data/local/DshaKeepalive
