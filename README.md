# Memory Monitor

Apple Silicon 原生 macOS 菜单栏内存监控器。Swift / SwiftUI / AppKit / Swift Charts；仅依赖系统框架，最低 macOS 14。无网络、账户、后台辅助程序或常驻脚本。

## 启动

双击 `dist/Memory Monitor.app`。菜单栏显示彩色圆点和已用内存；点击打开监控面板。面板底部可打开活动监视器、偏好设置或退出。点击外部关闭面板后继续采样。

建议将 `.app` 拖入用户的 `~/Applications` 或系统 `/Applications`，再打开并启用开机自启。默认关闭自启与通知。自启使用系统 `SMAppService.mainApp`；若系统要求批准，到「系统设置 → 通用 → 登录项」处理。更新应用前先退出旧版本，并保持应用路径不变。

此应用使用本地 ad hoc 签名，适合本机运行；未使用 Developer ID 签名或 Apple 公证，不作为已公证的跨机器发行版。无需关闭 SIP、Gatekeeper 或安装额外工具。

## 功能

- 默认 2 秒采样，可选 1 / 2 / 5 / 10 秒；单位 GB / 百分比，小数 0–2 位。
- 系统压力着色、物理总量、近似已用 / 可用、应用 / Wired / 压缩 / 缓存、Swap。
- 5 分钟 / 1 小时 / 24 小时趋势，历史仅驻留内存，重启清空。
- 面板打开时每 10 秒刷新可读取进程的前五名，关闭时停止扫描。
- 跟随系统 / 浅色 / 深色；原生独立设置窗口。
- 严重压力持续 60 秒才通知，冷却 30 分钟；用户主动开启时才申请通知权限。
- 休眠停止定时采样，唤醒立即采样；固定菜单栏宽度、等宽数字、无图表动画。

## 构建与检查

本机已具备 macOS 26.6、Apple Silicon arm64、Swift 6.3.3 和 Command Line Tools。无需第三方包或完整 Xcode。

在项目目录执行：

```sh
./scripts/build.sh
./scripts/check.sh
open "dist/Memory Monitor.app"
```

`build.sh` 构建 arm64 release、组装 `.app`、本地签名并验证签名。开发缓存保存在 `.build`。`check.sh` 执行有界历史及真实系统数据检查，不依赖 XCTest。应在普通 Terminal 环境运行；Codex 开发沙箱可能禁止 `vm.swapusage` 和进程查询，检查脚本需要在该沙箱外运行。应用本身未启用 App Sandbox，不要求管理员权限。

Swift Package 可直接用 Xcode 打开 `Package.swift` 阅读与调试。完整 Xcode 并非命令行构建必需。开发测试参数 `--show-dashboard` 可在启动时自动展开真实面板。

## 数据口径与限制

GB 按 1024³ 字节（GiB）显示，以匹配物理内存容量习惯。数值取同一次 `host_statistics64(HOST_VM_INFO64)` 快照，并使用系统页大小。

| 指标 | 计算方式 |
|---|---|
| 物理内存 | `hw.memsize`，诊断中与 `ProcessInfo.physicalMemory` 交叉验证 |
| 应用内存（约） | `max(internal_page_count − purgeable_count, 0) × pageSize`；匿名驻留内存近似值，非逐进程求和 |
| Wired | `wire_count × pageSize` |
| 压缩内存 | `compressor_page_count × pageSize`；压缩器物理占用，非压缩前逻辑大小 |
| 缓存文件（约） | `(external_page_count + purgeable_count) × pageSize` |
| 已用（约） | 应用 + Wired + 压缩，上限为物理总量 |
| 可用（约） | 物理总量 − 近似已用；含可回收资源，非仅空闲页 |
| Swap | `vm.swapusage.xsu_used`；读取失败明确显示不可用 |
| 排行 | `proc_listallpids` + `proc_pid_rusage(RUSAGE_INFO_V2).ri_phys_footprint` |

公开 VM 页计数无法完整复制活动监视器的所有内部归类（尤其系统和共享内存归属、新版 macOS 内部存储开销）。因此应用、缓存、已用和可用明确显示“约”，不承诺逐字节一致。没有将 GPU 内存再次加入统一内存总量。缓存是正常的可回收资源，高使用率本身不会触发压力颜色或提醒。

**压力来源**：主要使用公开的 `DispatchSourceMemoryPressure` 的 normal / warning / critical 事件。一旦收到事件，以事件为准。首次事件到来前，尝试只读 `kern.memorystatus_vm_pressure_level` 的 1 / 2 / 4 等级。该 sysctl 是内核兼容性接口，并非稳定公开契约；失败或出现未知值时显示灰点“等待系统状态”，继续等待公开事件。面板的压力帮助文字显示当前来源。三个事件等级并非活动监视器连续压力图的精确复制，瞬时颜色可能不同；没有用使用率阈值伪造压力。

进程按物理内存足迹排序，不聚合一个应用的全部辅助进程；它包括与该进程相关的物理负担，口径不同于 RSS，不能把排行榜相加作为系统已用。无法读取的进程（例如部分受保护系统进程）会跳过，不提权、不读取受保护内容。列表名称与图标只为显示，图标不可用时使用系统占位图。

历史上限：最近 5 分钟约 301 点，1 小时约 361 点，24 小时约 1441 点。长范围每个时间桶保留最后一次真实采样，因此不会完整呈现桶内的短暂尖峰。休眠期间没有采样；跨休眠的连接线只连接相邻有效采样，不代表休眠期间有观测。

## 源码结构

- `Sources/MemoryCore`：极小 C 桥接层，封装 Mach / sysctl / libproc，释放 Mach host port 和进程缓冲。
- `Sources/MemoryMonitor/Models.swift`：监控模型、独立后台采集队列、压力事件、有界历史、偏好持久化、通知。
- `Sources/MemoryMonitor/App.swift`：菜单栏、瞬态弹出面板、设置窗口、休眠唤醒、生命周期。
- `Sources/MemoryMonitor/Views.swift`：SwiftUI 面板、Swift Charts、设置和自启界面。
- `Sources/MemoryDiagnostics`、`Tests/HistoryChecks.swift`：真实系统诊断与有界历史测试。

## 验证情况

详见 `docs/VALIDATION.md`。已通过构建、真实数据诊断、历史上限测试、签名校验与短时运行抽查。**未达到 50 MB 常驻内存目标，也未完成全部人工交互、真实睡眠及长时间运行验收。**

参考：[Apple 内存指标说明](https://support.apple.com/en-nz/guide/activity-monitor/actmntr1004/10.14/mac/15.0)、[公开内存压力事件](https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure)、[登录项注册](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)。
