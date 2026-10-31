# DSHA: Daemon & Keep-Alive v3

目标：**让 `dsh.android.client` 压根不被杀**（不是"杀了再拉起"）。结构沿用 droidspaces 模块：`post-fs-data.sh` 铺底 → `service.sh` 编排 → `keepalived.sh` 常驻 root 守护。

## 本机实测到的三个真实死因（探测结果，不是推测）

| 现象 | 证据 | 后果 |
|---|---|---|
| AM 周期性 `Trimming phantom processes` 杀 `sh` | `logcat -b events`：`am_kill [0,23172,sh,0,Trimming phantom processes,3500]`，每 ~90s 一批 | 容器里的 shell 被砍，**正在跑的任务直接断** |
| phantom 阈值 32 | `dumpsys activity`：`max_phantom_processes=32` | 容器子进程一多就触发上面那条 |
| AM 会 trim cached 进程 | `max_cached_processes=1000`、`CUR_TRIM_CACHED_PROCESSES=166` | app 一旦变 cached 且排位靠后，就有被杀风险 |

另：`use_freezer=false`（本机没开 App Freezer），`dsh.android.client` 的 standby bucket = 5（ACTIVE）。

## 四道防线

1. **解除 phantom 限制**（最直接解决"任务被打断"）
   `device_config put activity_manager max_phantom_processes 2147483647`
   `settings put global settings_enable_monitor_phantom_procs false`
2. **保前台服务**：`dumpsys activity services` 检测 `isForeground=true`；服务在但不前台时 `am start-foreground-service -n …/HarnessService -a com.deepseekharness.app.PREPARE_WEB_START`（冷却 600s，避免反复 onStartCommand）。
3. **进程锁**：`oom_score_adj=-1000`（主进程 / `libproot.so` / `:shizuku`），LMK 与内核 OOM 都不选它；cgroup 冻结兜底写 0。
4. **系统策略**：appops 五项 allow、doze 白名单、`standby-bucket active`、关自适应省电，每 10 分钟重刷防厂商自愈。

兜底：20s 巡检，进程真没了才 `am start`（再失败走 `monkey`）。

## 极硬模式（`action.sh expert` 或 `MIGRATE_UID_CGROUP=1`）

把 app 进程从 `uid_10227` cgroup 迁到 `uid_0`，`am force-stop` / AM 的 `killProcessGroup` 就找不到它。代价：系统「强行停止」对它失效，部分安全统计失准。默认关闭，需要"绝不中断"时手动开一次（重启后自动恢复默认）。

## 安装 / 使用

```
1. 模块页安装 dsha-keepalive-v3.0.0.zip → 重启
2. 模块页「执行」           → 守护状态 + state
3. sh action.sh verify      → 四道防线逐项自检
4. sh action.sh expert      → 进极硬模式（可选）
```

## 能力边界（诚实）

- `SIGKILL` 本身无法被拦截：root 用户手动 `kill -9`、或厂商代码里硬编码的 kill，任何模块都挡不住。
- 模块挡的是**所有已知的系统与厂商回收路径**：LMK/内核 OOM、AM 的 cached trim、phantom 回收、Doze、后台限制、cgroup 冻结、以及常规 force-stop（极硬模式下）。
- 若仍被杀：`Logs/app.log` 里会留下 `lmkd`/`am_kill`/`powerkeeper` 记录，按记录针对性处理。
- 会话本身依赖 app 进程活着；容器（`libproot.so`）是 app fork 出来的，结构上无法被 root 事后接管——所以"不中断"的根在这四道防线上，而不在"重启快"。

## 会不会让容器/App 关不掉？

逐项结论（v3.1 实装）：

| 关闭方式 | 影响 |
|---|---|
| 在 App 里正常退出容器 / 退出终端 | **不受影响**。`oom_score_adj` 只影响 LMK 会不会选它，`exit`/`SIGTERM`/`SIGKILL` 照常生效；daemon 不持有容器进程，也不 watch 它 |
| 正常退出 App 本身 | **20s 内会被 daemon 拉起**（这正是保活的本意，也是唯一"感觉关不掉"的路径） |
| 系统「强行停止」/ `am force-stop` | 普通模式：会被拉起（显式 `am start` 会清掉 stopped 标记）；极硬模式：直接无效 |
| 卸载 / 禁用 App | 不受影响 |
| 内存紧张时被杀 | 不会被 LMK 杀；反过来说卡死时 LMK 也不会回收它，内存压力转移到别的进程 |

需要它真的能关掉时：

```
sh /data/adb/modules/dsha_keepalive/action.sh pause    # 临时：不拉起、不锁进程（重启后失效）
sh /data/adb/modules/dsha_keepalive/action.sh resume   # 恢复
```

永久停用：把 `config.sh` 里 `ENABLED=1` 改成 `0`（重启后不再起 daemon），或直接在管理器禁用模块。

另外 v3.1 加了**拉起熔断**：连续 5 次拉起失败会退避 600s，不会无限重启。

## WebUI（v3.2+）

模块根有 `webroot/index.html`，KernelSU / ReSukiSU 管理器会在模块页多出一个 **WebUI** 入口（不需要额外声明）。

- 状态卡：守护进程 / App 进程 / 前台服务 / `oom_score_adj` / `phantom 上限` / Doze 白名单 / standby bucket / 重启次数 / 防护开关
- 按钮：启动、重启、暂停防护、恢复防护、停止、刷新、四道防线自检、极硬模式
- 参数表单：巡检间隔、`oom_score_adj`、保持前台服务、解除 phantom 限制、模块启用 —— 保存后自动 `restart`
- 日志面板：最近 60 行 `keepalive.log`，5s 自动刷新状态

UI 通过 `webroot/ctl.sh` 执行全部操作；同一个脚本也能在终端直接跑：

```
sh /data/adb/modules/dsha_keepalive/ctl.sh status
sh /data/adb/modules/dsha_keepalive/ctl.sh pause
sh /data/adb/modules/dsha_keepalive/ctl.sh set INTERVAL 30
```

若管理器未注入 `ksu` API（老版本 ReSukiSU），页面会提示"只读"，此时用 `ctl.sh`。
