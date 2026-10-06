# Atoll 项目审计 — 2026-10-06

**判断：保留原生 AppKit + SwiftUI 方案。它适合轻量桌面常驻工具；当前版本仍需修正保存、任务释放和异常退出的边界，才能把“高性能、全天稳定使用”作为可靠承诺。**

当前正常使用的内存规模并不大。主要问题在大内容、错误路径和持续运行的资源管理。Extra Space 使用原生文本编辑器和后台原子保存是合理选择，继续保持单个连续文档即可。

## 审计范围和证据边界

- 审计本地工作树，基准提交 `27efb914a30a55391d28d6678354183d58d277a0`；工作树原有大量未提交修改，结论针对当前源码。
- 盘点 279 个 Swift 源文件及项目配置，检查主要子系统的数据路径、缓存、后台任务、子进程、网络、权限、窗口生命周期及测试覆盖。重点逐行检查持久化和资源释放路径。
- 读取应用专属目录的容量、数量及权限；没有读取实际便笺、会话正文、令牌或凭据。
- 采样已经运行的 Atoll，未重启、安装或自动启动生产应用；未调用 Claude CLI 或运行 Agent 的真实集成。
- 本次只新增报告、元数据证据和可重复的隔离探针，并为探针添加一条精确的 gitignore 例外；没有修改产品代码、删除数据、清理缓存、提交或发布。
- 这是项目级代码与资源审计。全天 soak、真实 AirDrop/蓝牙切换、全部 OS/硬件组合、Thread Sanitizer、依赖漏洞数据库与渗透测试仍未执行；未执行项目全部测试及真实 Agent 集成。

证据：

- [元数据及测试汇总](audit/2026-10-06/measurements.json)
- [隔离探针结果](audit/2026-10-06/probes.json)
- [可重复探针](../tests/audit_resource_probes.py)
- XCTest：`Build/Logs/Test/Test-DynamicIsland-2026.10.06_14-28-02--0700.xcresult`。
- 复现：`python3 tests/audit_resource_probes.py --output /tmp/atoll-audit-probes.json`。它只编译相关纯数据类和提取的管道解析器，使用临时文件与合成数据，不启动生产集成。

## 现场测量

测试环境为 arm64 MacBook Pro、macOS 27.0.1。10 次采样间隔 5 秒，总跨度 45 秒；开始时现有 Atoll 已运行约 1 小时 29 分钟。用户当时的交互与启用项没有受控，所以这是现场快照，不能作为严格的 idle 基准。

| 项目 | 观察值 | 解释 |
| --- | --- | --- |
| Atoll 主进程 RSS | 110.52–111.47 MiB | 首尾 111.20 → 111.47 MiB；短时没有明显持续增长 |
| ps CPU 样本 | 0–5.2% | 是 ps 的时间窗口值，不是瞬时功耗 |
| CPU time 增量 | 1.42 秒 / 45 秒 | 约一个逻辑核的 3.16%；未包含子进程开销 |
| 相关 XCTest | 149/149，通过 | 0 失败、0 跳过、0 runtimeWarnings |
| Python 检查 | 7/7，通过 | timer lifecycle、privacy configuration |
| 合成边界探针 | 4 组执行完成 | 复现问题和对照结果见下面；“执行完成”不代表缺陷已修复 |

149 个测试覆盖 Extra Space、Shelf、Now Playing payload、AudioTap 策略、Per-app volume 逻辑、Downloads、歌词解析/元数据、窗口承载、HUD 和布局等。通过这些测试不能推导出没有内存泄漏或可稳定运行 24 小时。

## 磁盘空间：开发占用与运行数据

以下为构建测试前的 `du` 分配空间快照，MiB = 1024² bytes。测试会继续增加 Build/Logs 等开发文件。父子目录数值不能相加。

| 位置 | 分配空间 | 类型和处理原则 |
| --- | ---: | --- |
| `Build/` | 2.75 GiB | 开发构建目录 |
| `Build/Intermediates.noindex` | 571.4 MiB | 编译中间产物 |
| `Build/SDKExplicitPrecompiledModules` | 495.6 MiB | SDK 模块缓存 |
| `Build/SourcePackages` | 479.3 MiB | 依赖检出与构建缓存 |
| `Build/InstalledBackups` | 264.6 MiB | 已安装应用回滚备份 |
| `Build/ModuleCache.noindex` | 235.4 MiB | 模块缓存 |
| `Build/Release` | 179.4 MiB | 发布构建及符号等 |
| `Build/Debug` | 154.7 MiB | 调试构建 |
| `Build/Logs` | 144.1 MiB | 测试结果与构建日志 |
| `.git/` | 178.0 MiB | 版本历史；不属于运行缓存 |
| `DynamicIsland/` | 15.2 MiB | 主应用源文件和资源 |
| `/Applications/Atoll.app` | 52.7 MiB | 实际安装应用 |
| `~/Library/Application Support/Atoll` | 48 KiB | AgentBridge 44 KiB、Extra Space 4 KiB |
| `~/Library/Application Support/DynamicIsland` | 8.98 MiB | 本次仅发现 TimerSounds |
| `~/Library/Caches/com.ebullioscopic.Atoll` | 80 KiB | 现存缓存目录；未删除 |
| 用户临时目录下 `Atoll/` | 本次不存在 | 该快照没有发现残留；不是永久保证 |

`Build/` 还存在约 50 MiB 一份的安装 staging 目录。开发占用可通过保留少量回滚版本和最近测试结果、清理可再生成构建缓存来控制；当前没有自动保留策略。应单独提供开发维护脚本，列出候选文件后执行，不将它混入产品自动清理。

运行数据同时使用 `Atoll` 和历史名称 `DynamicIsland`。目前不是重复保存缺陷，但会让用户误判哪些数据可以删。适合集中定义目录，并在未来迁移时保留兼容读取；Extra Space、Shelf JSON 和自定义声音属于用户数据，不能按缓存处理。

## 现有资源设计中值得保留的部分

| 子系统 | 已检查的限制和机制 | 仍需关注 |
| --- | --- | --- |
| Extra Space | 单一 NSTextView + NSScrollView；默认常规高度、内部滚动；500 ms 防抖、串行 utility queue、原子写入；读取失败保护原文 | 文本/撤销容量、恢复备份、重复保存 |
| Shelf 缩略图 | 48 项、8 MiB **计入的像素成本**、2 个并发请求、30 秒超时；取消与内存压力清理 | 不是整进程内存上限；键缺少文件版本 |
| Shelf 临时文件 | 普通文件保留引用；provider 文件异步复制；引用/lease/10 分钟 handoff；一个下一到期任务；60 秒创建宽限 | 活跃内容没有字节配额；恢复状态会保守保留文件 |
| Shelf 持久化 | 原子写入，损坏内容保留原始 recovery 副本，错误显示在 UI | 主线程全量 JSON 保存、无大小限额 |
| Agent | 40 条/会话、每消息 16,000 字符；30 分钟失活清理；最多持久化 60 会话；本机 loopback + bearer；目录 0700/文件 0600 | 整体字节预算与读取限制不一致；连接和旁路状态限额 |
| 歌词/音乐 | 歌词缓存 80 项，显式内容查询缓存各 300 项；歌词关闭即停止获取；请求取消和结果版本校验 | 只有项数限制；字节预算、管道解析与 EOF/取消 |
| Stats | 默认关闭；显示 Stats 后开始，关闭时默认停止；历史滑动窗口；最多 20 个进程；磁盘容量后台 30 秒刷新 | 部分硬件采集仍同步；进程结果缺少过期校验 |
| 下载检测 | 目录事件驱动，只有下载期间才进行 1 秒速度采样；目录扫描离开主线程 | 设置订阅未保留，关掉功能可能只隐藏 UI |
| Timer | endDate 倒计时，休眠不逐 tick 丢秒；原有自定义声音复制到 App Support | 音频导入在设置线程同步，替换不是完整事务 |
| Camera/Mic | 系统属性 listener 驱动，避免常规轮询 | 开关主要过滤显示，没有完全停止底层 listener |
| Bluetooth | system_profiler 快照 30 秒、后台电量获取和 in-flight 防重 | 3 秒常驻轮询，AirPods fallback 主线程命令 |
| Focus/System timer | Focus assertions 2 秒（有 leeway）或 log stream；System timer 默认镜像，日志 buffer 有 1 MiB 上限 | Focus 的另一条日志流缺少同样上限；stderr 管道处理需统一 |
| 天气 | ephemeral URLSession，10 秒请求/资源超时；成功结果默认缓存 30 分钟 | 定位等待、请求去重与失败重试缺少完整预算 |
| Audio | C++ 固定工作块、Accelerate、原子频段输出；Per-app volume render 无显式分配/锁/日志；无 taps 时不轮询 | gain 的跨线程同步；波形回调仍有 release 下日志代码 |
| 窗口/生命周期 | 保持固定外窗尺寸，显式 teardown 补足 borderless panel 的 onDisappear；VM destroy 清理 | 多显示器/休眠仍需 soak；私有系统接口的版本风险 |
| 日志/网络缓存 | debugLog 在 Release 编译掉；使用系统日志；shared URLCache 配置为内存 8 MiB、disk 0 | 不覆盖所有独立 URLSession/AVFoundation 缓存；ATS 全局放宽 |

依据包括 [ThumbnailService](../DynamicIsland/components/Shelf/Services/ThumbnailService.swift)、[ShelfFileLifetime](../DynamicIsland/components/Shelf/Services/ShelfFileLifetime.swift)、[TimerCountdown](../DynamicIsland/managers/TimerCountdown.swift)、[MusicManager](../DynamicIsland/managers/MusicManager.swift)、[架构说明](architecture.md)。

## 问题清单与优先级

P1：应在承诺高性能、全天常驻之前解决。P2：有实际缺陷或资源边界不足，列入下一轮修复。P3：较低影响的正确性/维护改进。每项区分复现结果和代码判断。

### F01 — P1：Agent 的保存可以生成自己无法读取的缓存，并阻塞主线程

**已复现，直接编译当前 AgentSession 和 AgentSessionStore；没有模拟其保存实现。**

- [AgentSessionStore](../DynamicIsland/managers/Agents/AgentSessionStore.swift) 第 5 行为 MainActor；193–201 行同步编码并写入。
- 第 52–53 行先完整读取 Data，再检查 8 MiB；过大的文件仍先被分配到内存。
- 写入侧第 196 行只限制 60 个会话，单会话的 40 × 16,000 字符可以远超整体读取预算。
- 合法上限合成数据的复测结果：1 会话 641,813 bytes，重新加载 1；14 会话 8,985,006 bytes，重新加载 **0**；60 会话 38,507,115 bytes，重新加载 **0**。
- 同步保存分别约 14、43、180 ms；首次独立实验最大为 173 ms。时间是本机合成负载样本，不是通常会话耗时。

影响：忙碌时输入/动画受全量编码写入影响；重启后缓存卡片消失。这是会话展示缓存，不等同于删除 Agent 自身的原始 transcript。

修正：一个整体字节预算同时约束写入/读取；读取前 stat；后台串行编码/写入；主线程仅取快照、提交状态；每次版本更新合并写入。过大或损坏的旧缓存应保留/解释，避免无声当成空数据。

### F02 — P2：音乐 JSON 流会丢失跨块的中文、emoji 等 UTF-8 内容

**已复现，探针提取当前 JSONLinesPipeHandler 原文。**

[NowPlayingController](../DynamicIsland/MediaControllers/NowPlayingController.swift) 第 525 行对每个任意读取块独立做 UTF-8 String 解码。字符跨块时两个块都可能解码失败，整块数据被丢弃。完整写入 `{"text":"你好🐳"}` 能读取一条；在中文首字节后拆块得到 0 条。

修正：用 Data 拼接，先找完整换行，再解码整行；加单行和积压的字节上限。按所有字节位置拆分中文/emoji 的测试要通过。它影响音乐更新流，不是 Extra Space 的粘贴编码。

### F03 — P2：关闭音乐管道时，等待中的任务未完成

**已复现。**

同文件第 552–568 行：readData 用 checked continuation 等待 readabilityHandler，close 却直接把 handler 设为 nil。取消 Task 没有替代性的 resume。探针输出 `CANCEL_AND_CLOSE_COMPLETED=false`，Swift 报告 leaked continuation。

影响：清理无法完成，等待链可能保留 controller。当前 MusicManager 单例只创建一次 controller，本次没有证据表明日常运行内存会因此线性增长。

修正：明确持有未完成的 continuation，EOF、错误、取消和 close 统一且恰好完成一次；关闭后禁止创建新等待。保留连续实例 start/stop 资源回归。

### F04 — P1：原生 HUD 抑制依赖暂停系统进程，异常退出缺少独立恢复保证

**代码确认；没有对用户系统执行强退或信号实验。**

[SystemOSDManager](../DynamicIsland/managers/SystemOSDManager.swift) 第 496–504 行对 OSDUIHelper 发 SIGSTOP。正常退出已有同步 SIGCONT 恢复（173 行以后），睡眠也会暂停 watcher，这些修复有价值。但 crash/SIGKILL 不执行 AppDelegate 的退出恢复；同一进程内的 watcher 也会消失。

影响：启用该抑制路径后，异常退出可能留下暂停的系统 HUD，影响原生亮度/音量等显示。

修正取舍：优先让原生 HUD 共存，减少系统进程操控。若保留完全替换，必须有独立、可审计的父进程死亡恢复与有界抑制租期。新增 helper 会增加部署和维护成本，应作为单独设计决定。异常退出验收应在受控环境做。

### F05 — P2：部分子进程先等待退出再排空管道，且缺少统一超时

**管道顺序的缺陷模式已复现；具体产品路径的发生条件另列。**

- [BluetoothAudioManager](../DynamicIsland/managers/BluetoothAudioManager.swift) 第 1969–1972 行在 MainActor 内调用 ioreg fallback；第 2121 行 waitUntilExit 后才读取输出。
- [DynamicIslandApp](../DynamicIsland/DynamicIslandApp.swift) 日志导出第 1182 行也采用此顺序，运行在后台。
- 合成进程写 1 MiB：未排空时 0.5 秒仍不能退出；开始读取后正常完成。管道容量有限，不能把输出较大时的写入和等待串行排列。
- **本机无沙箱限制的实际 `ioreg -r -l -w 0` 命令 exit 0、stdout 0 bytes、约 14 ms。没有复现它造成的应用挂死；该 fallback 在这次读取中也无法提供模式信息。**
- ZIP 已在后台处理，但 [TemporaryFileStorageService](../DynamicIsland/components/Shelf/Services/TemporaryFileStorageService.swift) 第 138–146 行没有取消或超时；挂载异常时可能长时间持有工作线程/lease。

修正：输出同步流式排空，或使用有界临时输出文件；为命令设置 deadline、取消和退出收尾。ioreg 查询与解析移出 MainActor，并验证能返回目标设备信息。日志导出需覆盖大输出及失败测试。

### F06 — P2：Downloads 设置订阅立即释放，开关不能可靠地控制后台监测

**代码确认 + Combine 生命周期对照已复现。**

[DownloadManager](../DynamicIsland/managers/DownloadManager.swift) 第 145–151 行的 sink 返回值没有存入属性/集合。全局搜索未发现其他负责该开关生命周期的观察者。对照探针：丢弃 sink 后收到 0 次后续事件，保留 sink 收到 1 次。

影响：启动时启用就继续监测，之后关闭可能仅由 ContentView 隐藏 UI；启动时关闭再开启也不能依赖这个订阅启动监测。下载扫描与计时器可能继续工作。

修正：保留 AnyCancellable，并测试“启动关闭 → 开启”和“下载中 → 关闭”的真实 manager 生命周期；开关关闭后 source、speed timer、队列结果均不得继续影响 UI。

### F07 — P2：Extra Space 没有文本/撤销预算，也没有上一版内容恢复

**代码确认；本次未进行真实大文档输入和内存压力实验。**

[ExtraSpaceStore](../DynamicIsland/managers/ExtraSpaceStore.swift) 第 96 行完整读文档；[ExtraSpaceEditor](../DynamicIsland/components/ExtraSpace/ExtraSpaceEditor.swift) 第 187 行每次更改提交完整 String，其他显示器更新也比较/替换整文档。[ExtraSpaceTextView](../DynamicIsland/components/ExtraSpace/ExtraSpaceTextView.swift) 第 9 行的 UndoManager 未设置 levelsOfUndo，默认没有组数限制。

读取、NSTextStorage、布局、保存快照和 undo 是不同内存成本。后台写文件不能消除主线程文本布局开销。连续大粘贴/删除/撤销可能显著增加内存；没有证据支持无限内容仍流畅。

原子写入保护单次替换，但不提供上一版历史。正常退出会 flush；异常退出可能丢失最后防抖期间尚未写入的内容。当前实际内容文件只有 114 bytes，本次没有读取正文。

修正：先测 100 KiB/1 MiB/5 MiB，再确定软容量预算，超限允许导出/选择处理，避免静默截断。限制 undo 组数并结合内容字节预算；保存合并相同 revision 的 in-flight 写入（Save、close、dismantle 可能重复排队）；保留一个 last-known-good 版本和一个简明恢复入口。无需为了单一小文档引入数据库。

### F08 — P2：Shelf 图片缓存有界，内容和持久化整体仍无预算

**代码确认。**

[ShelfStateViewModel](../DynamicIsland/components/Shelf/ViewModels/ShelfStateViewModel.swift) 第 28–34 行：MainActor 上每次 items didSet 全量同步保存；170–186 行添加没有总项数/文本字节预算；278–280 行导入队列没有排队预算。

[ShelfPersistenceService](../DynamicIsland/components/Shelf/Services/ShelfPersistenceService.swift) 第 70 行完整载入 JSON，第 102 行全量编码。用户可长期保留大量文本/provider 导入文件，48 张缩略图的限制不会限制这些内容或磁盘占用。损坏数据恢复时保守停止回收是正确选择，但需要 UI 指引，避免永远不知为何占用空间。

修正：后台串行保存、合并变更；显示 Shelf 自有文件总占用，设置导入大小/排队预算。保留在用文件与 handoff lease，不通过粗暴 TTL 删除有效内容。恢复副本允许用户检查/导出后处理，并定义有界保留政策。

### F09 — P2：Agent 和部分异步等待只有局部限制，缺少端到端资源预算

**代码确认；没有对真实服务做压力攻击。**

- [AgentEventServer](../DynamicIsland/managers/Agents/AgentEventServer.swift) 第 69 行有 2 MiB 单请求上限；117 行 accept 及 waiting 集合没有总体连接上限、未认证读取 deadline。slow local client 可以持有连接；stop 只处理已完成解析的 waiting replies，未完成请求未集中追踪。
- 单请求上限不能限制“许多同时请求”的总内存。loopback 和 bearer 仍有效，未发现远端公开监听。
- [AgentConversationService](../DynamicIsland/managers/Agents/AgentConversationService.swift) 的 drafts/errors/notices/transcriptStamps 等按会话保存；store 清除失活会话时没有统一回收这些旁路状态。长期许多不同 session ID 可留下内容/状态。
- Focus log stream [DoNotDisturbManager+Metadata](../DynamicIsland/managers/DoNotDisturbManager+Metadata.swift) 第 343 行缓冲没有长度上限；音乐流同样缺少行上限。SystemTimerBridge 已实现 1 MiB 上限，可借鉴。
- [LockScreenWeatherManager](../DynamicIsland/managers/LockScreenWeatherManager.swift) 第 1119 行等待定位回调，无取消/超时；refresh 缺少 in-flight 合并，失败时 lastFetchDate 不更新。
- [ProcessRunner](../DynamicIsland/managers/Agents/ProcessRunner.swift) 第 27/31 行仅 terminate；超时结果仍等待进程退出。忽略 SIGTERM 的进程无法满足硬 deadline。没有启动真实 AI backend 做验证。

修正：为 connections/tasks/buffers/files 四类资源分别设数量、字节、deadline 和 owner；关闭功能时统一取消/排空；会话回收通知旁路状态同步清理，非空 draft 可短期独立保留。天气用一个 in-flight 请求、定位 timeout 和失败退避。子进程仅对本次拥有的 PID/进程组执行有界退出，不扩大终止范围。

### F10 — P2：音量 gain 的跨线程 Float 访问绕过了并发检查

**代码确认；没有执行 TSAN 或验证可听见的故障。**

[AppVolumeTap](../DynamicIsland/audio/PerAppVolume/AppVolumeTap.swift) 第 41–44 行用 nonisolated(unsafe) Float，让 UI 写、render 第 228 行读取；注释以 arm64 对齐写不撕裂作为依据。硬件不撕裂并不替代 Swift 内存模型所要求的原子或同步操作。

修正：使用真正的原子标量，在回调只做 relaxed load；现有 C++ bridge 可以避免增加包和抬高 macOS 14.6 最低版本。不要在实时回调加 actor hop 或锁。另将 AudioTap 第 57–65 行周期诊断日志编译限制在 Debug；当前 Release 下仍计算峰值并调用 os_log。

依据：[Swift 官方 Memory Safety](https://docs.swift.org/latest/documentation/the-swift-programming-language/memorysafety/) 对 atomic 与 nonatomic 访问的定义；[Swift 5.10 并发说明](https://www.swift.org/blog/swift-5.10-released/) 解释 unsafe 标记需要自行保证同步。

### F11 — P2：网络及本地内容权限基线可收紧

**配置和元数据确认；没有发现或模拟数据外泄。**

- [Info.plist](../DynamicIsland/Info.plist) 第 5–8 行 `NSAllowsArbitraryLoads=true` 全局放宽 ATS。主要天气/歌词服务使用 HTTPS，本地桥接也只需本地能力，应验证具体依赖后用更窄例外。
- Extra Space 目录 0755、文件 0644；Shelf 默认创建也未指定保护权限。AgentBridge 已使用 0700/0600，可统一用户内容的基线。
- **本机 Library 和 Application Support 均为 0700，因此不能从 Extra Space 的 0644 推导出其他账户当前能读取。** 同用户运行的其他进程不因改成 0600 就被隔离。
- 应用 entitlement 没有 App Sandbox，并禁用 library validation；结合跨应用 Accessibility、私有系统接口等需求是有成本的取舍，不能把“Saved locally”解释为加密存储。

修正：用户内容目录 0700、文件 0600；基于具体域名/本地连接配置网络例外；按实际启用项申请权限。无需强迫用户为无关功能授权 Full Disk Access。

依据：[Apple NSAllowsArbitraryLoads](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloads)，全局例外会降低 ATS 保护，宜收窄。

### F12 — P2：高内存提示的重启流程在新实例启动失败时仍退出旧实例

**代码确认。**

[MemoryUsageMonitor](../DynamicIsland/managers/MemoryUsageMonitor.swift) 第 103–107 行记录 launch error 后仍 terminate 当前 app。新旧实例的数据交接也没有“先 flush、后读取”的显式次序。

这不是内存硬上限：只在启动和系统 memory-pressure 事件中测量；Release 1 GiB 是提示阈值。低频、事件驱动的设计省电，但不能依靠该提示代替各缓存的实际预算。

修正：launch 失败保留旧实例并显示失败；启动前完成重要数据 flush；保证单个 writer/清晰 handoff。测试启动失败、未保存文本、双实例竞争和 OSD 恢复次序。

### F13 — P3：缩略图键没有包含文件版本

[ThumbnailService](../DynamicIsland/components/Shelf/Services/ThumbnailService.swift) 第 68 行以 path + size 作键。在同一路径修改内容后可继续命中旧缓存。rename 路径已有全量 clear，但不能覆盖外部原位修改。

修正：将文件修改时间/size 或版本标识纳入 key；不要因为修改一张图清掉所有图。此次是代码判断，未执行真实文件原位修改的视觉验收。

### F14 — P3：部分停止后的异步结果、设置导入与测试初始化仍需收尾

- Stats 第 1119–1126 行后台进程采样回来后缺少 isMonitoring/generation 检查；stop 把 in-flight 标志重置，新旧采样可能交错。磁盘采样第 778 行已有 monitoring 校验，可统一。
- SettingsView 第 3926 行同步读/写任意尺寸 custom icon；第 6278 行同步复制 timer sound。大量导入会影响设置响应。TimerSoundStore 第 74 行先删除旧声音，再 move 新声音，失败路径不保证旧文件仍在。
- AppDelegate 的实例属性（110–118 行）在 applicationDidFinishLaunching 的测试 guard 前创建若干 singleton。测试会启动部分 Bluetooth/SystemTimer 活动；真实集成启动被 guard 阻止。适合提供显式 runtime-services 容器，测试注入 inactive 服务。
- Camera/Mic 开关当前主要控制显示，Bluetooth 3 秒 fallback 轮询在初始化即开始且无 tolerance。明确每个设置的实际监测语义，并在完全无需监测时停掉；保留真正需要持续工作的功能。
- 项目还声明了 open-meteo package reference，但当前没有对应 product dependency 或 SDK import；天气使用自己的 URLSession/Decodable 实现。其 checkout 本次占 4.1 MiB。可在后续依赖整理中确认后移除旧引用；本次没有修改包配置。

以上不应扩展为无差别大重构。逐项加入结果版本、后台导入或生命周期门控即可。

## 方案是否适合高性能、长期使用

**适合继续使用原生架构；按当前实现，不适合承诺“任意内容量、全天候无卡顿”。** 正常个人使用和资源受限的高性能方案之间，缺少的是可执行的资源预算、错误路径和长期验证。

建议的实现原则：

1. UI 主线程只做输入、选择和轻量快照；编码、文件操作、系统命令和大解析用串行 utility queue/actor，结果按 revision/generation 回传。Apple 建议将非 UI 重工作移出主线程，并把连续交互的主线程工作压到约 5 ms：[Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)。
2. 开关关闭、页面不可见、锁屏/休眠是明确的生命周期输入。只暂停不再需要的工作；音乐播放、有效音量 taps、计时器等所需活动继续。优先事件通知，低频 fallback 加 tolerance/leeway：[Apple Mac Energy Efficiency Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/BestPractices.html)。
3. 把用户文档、可重建缓存、临时 handoff、开发备份分开：有用内容不自动删；缓存可淘汰；临时文件须尊重 lease；开发备份有保留数。
4. 每个后台工作必须能取消、超时、完成恰好一次；每个数据容器有项数及字节预算。不能仅依赖“很多单例”或“内存高了提醒重启”。
5. 保留现有本地小文件保存；多文档/查询成为真实需求时再考虑 SQLite。限制缺失不会因为换数据库或换 UI 技术栈自行消失。
6. MediaRemote 私有框架（NowPlayingController 第 61 行）、SkyLightWindow、动态 selector、系统 log 文本解析增加 macOS 更新维护成本。将它们封装成可降级适配器；升级 OS 时单独验证。当前纯原生技术本身并不保证私有接口长期兼容。
7. Package.resolved 固定了 10 个依赖的具体 revision；其中若干依赖以 main 分支管理，后续 resolve/update 应审核差异。当前没有执行在线 CVE 扫描，不能声明依赖完全没有安全问题。

## 建议的修复顺序和验收

| 顺序 | 修复包 | 可验收结果 |
| --- | --- | --- |
| 1 | Agent 保存预算/后台写入，音乐字节解析及取消 | 合法边界保存后可重载；UI 没有同步大编码；所有字节拆分一致；EOF/close/cancel 完成且无 continuation 警告 |
| 2 | OSD 异常恢复、重启失败保留旧进程、子进程超时 | 受控异常退出后原生 HUD 恢复；启动失败旧 app 继续；命令大输出和超时不悬挂 |
| 3 | Downloads 订阅、功能门控、旁路状态回收 | 关闭后 listener/timer/task 归零；30 分钟过期 session 对应状态能释放 |
| 4 | Extra Space/Shelf 文本、undo、磁盘预算与恢复 | 1/5 MiB 负载下行为明确；未静默删内容；Save/恢复及错误提示可验证 |
| 5 | 原子 gain、权限/ATS、cache version、低影响收尾 | 并发检查与音频压力通过；更窄权限生效；原位更新得到正确缩略图 |

修复后应做 24–72 小时 soak，记录主进程**及子进程** CPU time、RSS/physical footprint、fd、thread/task、连接数、专属目录字节数以及 MainActor/hitch 时间。场景包含：

- 全部可选功能关闭；开启实际常用功能；音乐/音量 taps 连续工作。
- Extra Space 100 KiB、1 MiB、5 MiB 连续编辑/粘贴/撤销；Save、关闭与重启；多显示器交替编辑。
- Shelf 重复大量导入、拖出/分享/剪贴板 lease、删除、损坏恢复、低磁盘空间及不可达网络文件。
- 合成 Agent 高频事件、连接超时、缓存边界；真实集成另行验证，遵守 CLI 授权边界。
- 反复开关功能、睡眠/唤醒、锁屏/解锁、接拔显示器、蓝牙和音频路线切换。
- 在隔离环境模拟 crash/force quit、写入错误、损坏文件、重启失败。

**建议工程预算，尚非实测通过标准：**连续交互主线程工作 p95 < 5 ms、离散操作没有 >100 ms 的应用主线程长任务；受控全关闭稳态主进程 CPU 平均 < 一个核的 0.5%。暖机后空闲内存回到稳定区间，重复 100 次交互或 24 小时观察中没有无法解释的持续增长；增量增长 >10% 应调查，不能仅用百分比判定泄漏。项目资源计数应回落到定义的 baseline，完整 notes 的 Save 确认必须基于写入结果。

本次已完成源码与目录审计、短时现场采样、149 + 7 检查及可重复边界复现。产品修复和长期/真实设备验收均未在本次执行。
