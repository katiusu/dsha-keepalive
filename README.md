<div align="center">

# DSHA Keep-Alive

**为 [DSHA](https://github.com/DSH-APP/DSHA)（DeepSeek Harness 的 Android 客户端）设计的 KernelSU 保活模块**
*KernelSU / ReSukiSU module built for DSHA — keeps its container alive: not "restart faster", but "never get killed".*

![version](https://img.shields.io/badge/version-v3.3.0-2ea44f)
![platform](https://img.shields.io/badge/platform-Android%2011%2B%20(aarch64)-3ddc84)
![root](https://img.shields.io/badge/root-KernelSU%20%7C%20ReSukiSU-blue)
![license](https://img.shields.io/badge/license-MIT-lightgrey)

配套客户端：[**DSH-APP/DSHA**](https://github.com/DSH-APP/DSHA) · 本模块为它而写

</div>

---

## 概述

DSH Android 客户端（`dsh.android.client`）在设备内运行一个 PRoot Ubuntu 容器，会话与任务都依赖这个容器进程存活。厂商 ROM 的后台回收策略会周期性地把它连同容器内的 `sh` 一起杀掉，正在执行的任务随之中断。

本模块从**内核与 Android 框架层**消除这些回收路径：调整 `oom_score_adj`、解除 phantom process 限制、观察前台服务状态、写 Doze / standby 白名单，并常驻一个 20 秒轮询的 root 守护进程做状态回写。结构参考 [droidspaces](https://github.com/ravindu644/Droidspaces-OSS)：`post-fs-data.sh` 铺底 → `service.sh` 编排 → `keepalived.sh` 常驻。

**模块不做拉起。** 它只负责让正在跑的进程不被系统回收；App 一旦退出，模块只写一行 `app gone` 日志，等你手动打开——不开 App、不 `am start`、不 `monkey`、不碰容器生命周期。任何模式（含极硬模式）都成立。

## 关于 DSHA：本模块的服务对象

本模块**专为 [DSH-APP/DSHA](https://github.com/DSH-APP/DSHA) 设计**，不是通用保活模板。

[DSH-APP/DSHA](https://github.com/DSH-APP/DSHA)（`applicationId = dsh.android.client`，MIT）是「免 ROOT 免 Termux，在手机上跑 DeepSeek Harness」的 Android 客户端：它把完整 Ubuntu 环境与 proroot 引擎内嵌进 App 进程，让 DSH 直接在手机本地运行。

正因为容器是 **App 进程 fork 出来的子进程**，厂商 ROM 一旦回收 App，容器连同其中的会话与任务一起消失——这就是本模块存在的理由。模块内的目标常量全部取自该客户端的真实结构，而非猜测：

| 常量 | 值 | 来源 |
|---|---|---|
| `PKG` | `dsh.android.client` | 上游 `app/build.gradle` 的 `applicationId` |
| `COMPONENT` | `dsh.android.client/com.deepseekharness.app.ui.MainActivity` | 上游启动 Activity |
| `SERVICE` | `dsh.android.client/com.deepseekharness.app.HarnessService` | 上游前台服务 |
| `SERVICE_ACTION` | `com.deepseekharness.app.PREPARE_WEB_START` | 上游服务 action |

配套关系：DSHA 负责在手机本地运行 DSH 与容器，本模块负责**让这个容器不被系统回收**。两者可以独立升级；若上游更换包名或组件名，同步修改 `config.sh` 顶部常量即可。

> 本项目为面向 DSHA 的社区配套模块，与 DSH-APP 上游无隶属关系。

## 特性

| | 能力 |
|---|---|
| 🛡 **LMK / 内核 OOM 免疫** | `oom_score_adj=-1000`，覆盖主进程、`libproot.so`、`:shizuku` 子进程 |
| 🧹 **解除 phantom 限制** | `max_phantom_processes` 抬到上限并关闭 phantom 监控，消除 `Trimming phantom processes` 连坐 |
| 📌 **前台服务观察** | 检测 `HarnessService` 的 `isForeground` 并写入状态，不主动拉起服务 |
| 💤 **系统策略豁免** | appops 五项、Doze 白名单、`standby-bucket active`、关自适应省电，每 10 分钟重刷防厂商自愈 |
| 🔁 **精确判活** | 以 `argv[0]` 精确匹配主进程，避免 `:shizuku` 残留导致"以为还活着"；判到不在也只记录 |
| ⚙️ **完整 WebUI** | 管理器模块页内直接查看状态、启停、改参数、看日志，无需终端 |
| 🚫 **永不拉起** | 没有任何 `am start` / `monkey` / 容器启动路径；关掉就是关掉 |
| 🧩 **无侵入** | 不改 app、不注入进程、不 hook；卸载模块即完全还原 |

## 工作原理

```
post-fs-data.sh   建目录（不启动 app、不启动容器）
      ↓
service.sh        等 sys.boot_completed → 启动 keepalived.sh → 回写模块描述
      ↓
keepalived.sh     每 20s 一轮：判活 → 锁进程 → 观察 FGS → 策略维护 → 回写状态
```

**四道防线**

1. **phantom 解除** — `device_config put activity_manager max_phantom_processes 2147483647`、`settings put global settings_enable_monitor_phantom_procs false`
2. **前台服务观察** — 读 `dumpsys activity services` 的 `isForeground` 写进状态文件，不主动拉起服务
3. **进程锁** — 写 `oom_score_adj=-1000`；`use_freezer` 开启时额外写 `cgroup.freeze=0`
4. **系统策略** — appops allow ×5、doze 白名单、standby bucket active、关闭自适应省电

**没有兜底拉起。** 进程判到不存在时，守护只记一行日志并继续写状态；恢复由你手动打开 App，或由客户端自身的 `AdbKeepAliveReceiver` 广播负责。

## 兼容性

| 项目 | 要求 |
|---|---|
| Android | 11+（`oom_score_adj` / FGS / `device_config` 可用） |
| 架构 | aarch64 |
| Root | KernelSU / ReSukiSU（走模块机制）；Magisk 理论可用但未验证 |
| 管理器 | ReSukiSU 管理器、KsuWebUI、MMRL 均可打开 WebUI |
| 已测机型 | Redmi K40（alioth / SM870），内核 4.19.325，KernelSU `u:r:ksu:s0` |
| 目标客户端 | [DSH-APP/DSHA](https://github.com/DSH-APP/DSHA) `dsh.android.client` 0.2.1-rc.2 |

## 安装

1. 从 [Releases](https://github.com/katiusu/dsha-keepalive/releases) 下载 `dsha-keepalive-<version>.zip`
2. 管理器 → 模块 → 从本地安装 → 重启设备
3. 打开 DSH 客户端（模块不会自启它；之后守护只负责让它**不被杀**，退出后不会把它叫回来）
4. 管理器模块页 → 打开 WebUI 查看状态

## 使用

### WebUI

模块内 `webroot/index.html` 由管理器自动加载，无需额外声明。

- **状态卡**：守护进程 / App 进程 / 前台服务 / `oom_score_adj` / phantom 上限 / Doze / standby bucket / 重启次数 / 防护开关
- **操作**：启动 · 重启 · 暂停防护 · 恢复防护 · 停止 · 刷新 · 自检 · 极硬模式
- **参数**：巡检间隔、`oom_score_adj`、保持前台服务、解除 phantom 限制、开机自启 app、模块启用（保存后自动重启守护）
- **日志**：最近 60 行 `keepalive.log`，状态 5 秒自动刷新

页面顶部常驻两个独立字段，分别回答两个不同的问题：

- **执行通道**：管理器是否把执行接口注入本页面（`ksu` / `ksud` / `mmrl` / `MMRL` / `$ksu` / `KernelSU`，显示为「已注入」或「未注入」）
- **数据来源**：本次状态数据从哪里来（`实时命令` 或 `静态快照 status.txt（最多迟 60s，只读）`）

两者互不推断：注入成功但调用被拒绝，也会明确写成「执行通道：ksu（已注入）｜数据来源：静态快照」。点「诊断」可直接看到 `exec` 的原始返回值（`id` 输出、`ctl.sh status` 前 12 行、返回类型与长度），以及六个候选接口在 `window` 上的真实类型。

### 命令行

```sh
M=/data/adb/modules/dsha_keepalive
sh $M/webroot/ctl.sh status        # 键值对状态
sh $M/webroot/ctl.sh start|stop|pause|resume|restart
sh $M/webroot/ctl.sh verify        # 四道防线逐项自检
sh $M/webroot/ctl.sh log 60        # 最近 60 行日志
sh $M/webroot/ctl.sh set INTERVAL 30
sh $M/action.sh expert             # 极硬模式（见下）
```

### 主要参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `ENABLED` | `1` | `0` = 模块整体停用 |
| `INTERVAL` | `20` | 守护轮询间隔（秒） |
| `OOM_ADJ` | `-1000` | 进程 `oom_score_adj`；`-1000` 为 LMK/OOM 免疫 |
| `DISABLE_PHANTOM_LIMIT` | `1` | 解除 ActivityManager phantom process 限制 |
| `FORCE_FGS` | `1` | 观察 FGS 是否在前台（只记录，不拉起） |
| `UNFREEZE_CGROUP` | `1` | 持续写入 `cgroup.freeze=0` 兜底 |
| `MIGRATE_UID_CGROUP` | `0` | 极硬模式：把进程迁出 `uid_<app>` cgroup（只防杀，不拉起） |
| `OPT_DISABLE_DOZE` | `0` | 关闭整机 Doze（激进，默认关） |

### 状态与日志

| 路径 | 内容 |
|---|---|
| `/data/local/DshaKeepalive/state` | 守护实时状态键值对 |
| `/data/local/DshaKeepalive/Logs/keepalive.log` | 守护日志 |
| `/data/local/DshaKeepalive/Logs/app.log` | `lmkd` / `am_kill` / `powerkeeper` / ANR 采集 |
| `/data/adb/modules/dsha_keepalive/webroot/status.txt` | WebUI 降级用状态快照 |

## 极硬模式

```sh
sh $M/action.sh expert        # MIGRATE_UID_CGROUP=1，重启守护生效
```

把 app 进程从 `uid_10227` cgroup 迁至 `uid_0`，AM 的 `killProcessGroup` 与 `am force-stop` 因而打不到它。代价：系统「强行停止」失效、部分安全/统计逻辑失准。默认关闭，重启后回到默认。

极硬模式**同样不含任何拉起逻辑**：它只让 kill 打不到，不会在你关掉 App 之后把它叫回来。

## 如何真正关掉它

| 关闭方式 | 结果 |
|---|---|
| App 内正常退出容器 / 终端 | **不受影响**，`exit`/`SIGTERM`/`SIGKILL` 照常生效 |
| 正常退出 App | **不会拉起**，模块只记一行 `app gone` 日志 |
| 系统「强行停止」 | **不会拉起**；极硬模式下进程可能残留，随时可 `ctl.sh stop` |
| 卸载 / 禁用模块 | 立即停止干预 |
| 内存紧张 | 不会被 LMK 选中，压力转移到其他进程 |

需要它安静下来时：

```sh
sh $M/webroot/ctl.sh pause     # 临时：不写策略、不锁进程（重启后失效）
sh $M/webroot/ctl.sh resume    # 恢复
```

永久停用：`ENABLED=0`，或直接在管理器中禁用模块。

## 故障排查

| 现象 | 排查 |
|---|---|
| WebUI 状态全空 | 看顶部「exec 通道」行；管理器未注入 API 时依赖 `status.txt` 快照，确认守护是否在跑（`ctl.sh status`） |
| 按钮无反应 | 确认 `webroot/ctl.sh` 有执行权限；直接跑 `sh $M/webroot/ctl.sh status` 看报错 |
| 守护未运行 | `cat /data/local/DshaKeepalive/Logs/keepalive.log`；`ctl.sh start` 手动启动 |
| 仍被杀 | 查 `Logs/app.log` 里的 `lmkd` / `am_kill` 记录；必要时开极硬模式 |
| App 退出后没被恢复 | 预期行为：v3.3.0 起模块不再拉起，请手动打开 App |
| 界面手提示「守护还在跑旧版本」 | 升级模块后旧进程不会自动退出：点「重启守护」（= `ctl.sh reload`），或重装（`customize.sh` 会结束旧进程） |

## 能力边界

- `SIGKILL` 无法被拦截：root 手动 `kill -9`、厂商硬编码 kill 都挡不住。
- 模块**不负责拉起**：进程真的没了就没了，恢复由你或 App 自身的 `AdbKeepAliveReceiver` 负责。
- 模块消除的是**已知的系统与厂商回收路径**：LMK/内核 OOM、AM cached trim、phantom 回收、Doze、后台限制、cgroup 冻结，以及常规 force-stop（极硬模式下）。
- 容器由 app fork 出来（`libproot.so --kill-on-exit`），无法被 root 事后接管，因此"不中断"的根在防线本身，而非重启速度。
- 极端内存压力下，免疫进程会使 LMK 转而回收其他应用，属预期代价。

## 许可

[MIT](LICENSE) © 远方缘分的天空
