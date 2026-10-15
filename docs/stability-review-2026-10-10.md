# Atoll 长期稳定性复核与调试方案

> 此文保留修复前的审计基线。随后 `fix all` 的改动、验证结果与未完成真机验收见[稳定性修复记录](stability-fixes-2026-10-10.md)。

日期：2026-10-10。结论：保留原生 AppKit + SwiftUI 架构，进入稳定性加固阶段。现有测试基础已经可用，但普通退出的数据保护、诊断日志、部分子进程和服务恢复仍有缺口；不能据此承诺全天长期稳定。

本轮要求：①给出长期使用的调试方法；②复核当前风险及旧问题的修复状态；③提供验证证据、优先级和可执行的验收标准。本轮只新增审查文档与证据，没有修改产品代码、安装或重启正式应用。

## 范围与证据边界

- 对当前工作树检查，而非只检查 HEAD。原有 Stats 性能改动及文档均保留。
- 检查启动/退出、持久化、进程/管道、Agent 接入、Stats、日志、音乐/音频、Focus、Timer、网络/天气、权限、私有系统接口、构建和 CI；结合现有各子系统回归。
- 测试环境为 arm64、macOS 27.0.1、Xcode 27.0，项目 Swift 5 模式；应用部署目标为 macOS 14.6。单机成功不能代表全部支持系统。
- 原生测试复制到临时目录，使用独立 bundle ID、独立偏好域和测试内容目录。真实 Agent CLI、配置、凭据和会话均未访问；Agent 验证只用项目 fixture。
- 未运行 24–72 小时 soak、真实多屏/休眠/音频切换、Thread Sanitizer、Address Sanitizer、Instruments 性能采集、真实 Agent 集成或发行签名/公证验收。没有把这些项目记成通过。
- 本报告是主要子系统审查与回归验证，不是每行源码的形式化证明，也不是完整渗透测试或依赖漏洞审计。

本轮结果及源码指纹见 [验证记录](audit/2026-10-10-stability/verification.json)，原生测试摘要见 [native-summary.json](audit/2026-10-10-stability/native-summary.json)。

| 本轮实际执行 | 结果 |
| --- | --- |
| Debug build-for-testing / Release build | 均成功；签名关闭，仅本地构建，既有编译警告仍在 |
| 全量原生单元测试 | 311 通过，0 失败、0 跳过；xcresult 的 runtimeWarnings 为空 |
| Python privacy / timer lifecycle | 7 通过 |
| Agent 对话/RPC 隔离回归 | 16 组通过；未调用真实 CLI |
| 插件队列回放 | 7 组通过；模拟子进程 |
| Guardian 异常恢复 | 4 个合成案例通过；仅操作自建 sleep 进程 |
| 精确源码资源探针 | UTF-8 分块、取消完成、1/14/60 会话重载正常；另有管道/订阅对照 |

原始测试 stdout 仍有系统 linkd/Quick Look 等非致命诊断，不把汇总中的空 runtimeWarnings 解释为进程从未打印任何 warning。

## 已有修复：保留，不重复重写

| 范围 | 当前保护和本轮证据 | 剩余边界 |
| --- | --- | --- |
| Extra Space / Shelf | 后台保存、原子替换、大小限制、Extra Space 上一版恢复、Shelf 文件 lease 和导入预算；相关 XCTest 通过 | 写盘失败时的普通退出、真实磁盘满/卷断开、强退时未落盘编辑 |
| Agent 缓存与传输 | 8 MiB 文件预算、连接/请求/缓冲限额、超时、UTF-8 分块和取消；60 个合成会话全部重载 | 真实外部协议版本、服务失败后的恢复；预览缓存不等于原始 transcript |
| Stats | 后台串行采样、合并请求、代次校验、按详情需求采集；9 个 Stats 测试通过 | 本轮没有测完整 UI 的帧耗时或长期功耗；磁盘卷查询仍可能阻塞底层 I/O |
| OSD | 独立 guardian，检查 UID/名称/出生时间；4 个仅对 sleep fixture 的恢复案例通过 | guardian 自身被 SIGKILL、双进程同时死亡、真实系统 HUD/OS 兼容 |
| Timer / Calendar / 开关 | deadline 倒计时、代次清理、按需求查询、统一 tab 回退、关闭 Shelf 保留内容；相关测试通过 | 真机休眠跨到期、日期/时区变化、功能并存 |

之前记录为失败并被排除的 `testFeatureManagementDestinationRendersInTheSettingsWindow`，本轮包含在全量原生测试中并通过。它不再是“当前必现失败”；历史失败仍提示测试对环境/时序的敏感性，应接入 CI 持续观察。

## 当前风险与修复验收

P1 表示应在“可放心长期使用”之前处理；P2 表示下一批加固；P3 表示维护性改进。源码路径确认与真实故障复现分别标注。

### R01 · P1 · 普通退出遇到保存失败，仍可能丢失最后修改

**源码确认，未让正式应用发生写盘故障。** `DynamicIslandApp.swift:238` 的 `applicationWillTerminate` 调用三个 flush 后继续退出；未实现 `applicationShouldTerminate(_:)`。`ExtraSpaceStore.swift:101` 会保留 dirty/error，但退出流程不检查它。磁盘满、目录权限改变等情况下，已经落盘的旧文件有保护，尚未保存的编辑仍可能随进程退出消失。

重启入口 `MemoryUsageMonitor.swift:122` 已检查部分保存错误，普通 Quit 尚未共享这一保护。同步 `persistenceQueue.sync` 还意味着异常文件系统 I/O 可能延长退出。

修复：将普通退出和重启收敛到同一保存协调器，先结束输入法组合文本，完成持久化再退出；失败保留进程，提供重试/导出/明确放弃。可采用 AppKit 的 `terminateLater` / `terminateCancel` 协议，不把错误处理放在已开始终止的回调里。[Apple 退出协议](https://developer.apple.com/documentation/appkit/nsapplication/terminatereply)

验收：用临时文件系统 fixture 注入拒绝写入/空间不足/慢保存，覆盖 Quit、重启、输入法未提交状态；失败后仍能找回并导出最后编辑。强退窗口应明确标注为“未保存”，不声称原子写入能保护尚未写出的内容。

### R02 · P1 · 日志导出漏掉主要模块，默认 Release 又缺少关键错误记录

**源码确认 + 合成谓词复现。** `utils/Logger.swift:86` 使用 `com.ebullioscopic.Atoll`，`DynamicIslandApp.swift:1170` 只导出 `com.Ebullioscopic.Atoll` 和 `.dev`；`audio/AudioTap.swift:34` 使用另一个 subsystem `com.atoll.dynamicisland`。当前相等谓词对通用 Logger 和音频 subsystem 均返回 false，见 [谓词探针](audit/2026-10-10-stability/log-predicate-probe.md)。这不是“完全没有日志”：Timer 等使用大写 subsystem 的模块仍能匹配。

另外，`models/Constants.swift:450` 的 Release 默认级别为 `.none`，自定义 Logger 的 error 也会被过滤；所有自定义级别最终都以 `.default` 写 OSLog。`AgentBridge.swift:87` 的失败还归为 `.agents` 信息级别。出问题后再打开日志不能恢复过去未记录的内容。

修复：统一 subsystem 常量和真实 severity；默认保留经过脱敏、限频的 error/fault 与关键恢复事件。常规细节仍按需打开。诊断包带构建指纹、功能开关、权限状态、错误码、最近状态迁移、主/helper 资源计数；不带正文、prompt、token 或完整路径。导出覆盖全部实际 subsystem。

验收：隔离 Release 主动生成每个模块的合成错误，导出后逐条验证；关闭详细日志仍能定位错误；确认包中无测试假 token/正文。不要简单把全量 Debug 日志长期开启。

### R03 · P1 · 部分子进程仍绕开已有超时和并发排空机制

**源码确认；通用管道阻塞机制由合成探针复现，真实命令卡死未复现。**

- `DoNotDisturbManager.swift:543` 的初始 Focus 查询依次查 5m/1h/24h，`waitUntilExit()` 在读取 stdout 之前，stderr 未排空、无 deadline。较大日志可以使子进程写满管道，永久占住串行 metadata queue。
- `KeyboardBrightnessSensor.swift:111` 的 `corebrightnessdiag` fallback 无超时；`SystemKeyboardBacklightController.swift:43` 的 `adjust` 同步取 `currentLevel`，由 `SystemChangesObserver.swift:212` 的按键路径调用。主私有 API 失效才进入兜底，不能把风险描述为每次按键都会阻塞。
- `SystemTimerBridge.swift:333` 停止 log stream 时 TERM 后无限等待；`NowPlayingController.swift:112` 的孤儿清理、录屏检测的 pgrep/killall 也有无 deadline 的等待。
- `Terminals/AgentTerminals.swift:72` 有进程 deadline，但输出在退出后读取。大输出会变成不必要的超时；继承输出管道的后代还可能使读取迟迟没有 EOF。

修复：短命令统一使用 `ProcessRunner.capture`，后台执行、同时排空两条流、输出限额、取消和明确 deadline；长时间流采用受控 owner、EOF/退出处理和停止 deadline。对 `ProcessRunner.captureBlocking` 的内核阻塞边界也不能承诺绝对硬超时。

验收：大 stdout/stderr、忽略 TERM、永不结束、后代持有管道、快速开关/取消；UI 保持可交互，持有的任务/FD/进程有界，不能留下持续增长的队列。

### R04 · P1 · 自动验证尚未覆盖现有原生测试

**配置确认。** `.github/workflows/ci.yml` 只执行两组 Python 检查和 `xcodebuild build`，不执行 XCTest；PR 触发分支只含 `dev`。项目已有 311 个原生测试，却未构成每次改动的保护网。UI 自动化在无桌面 runner 不便运行，不能据此把所有单元测试一起排除。

修复：一条命令完成独立测试宿主准备、单元测试、纯 Swift/Agent fixture、Python、guardian fixture、Release 构建；接入实际使用分支的 PR CI。纯逻辑可逐步拆成无宿主 target，AppKit 集成保留独立宿主；只在可靠桌面环境执行真正的 XCUITest。

验收：干净 checkout 可复现；故意破坏一个断言使 CI 变红；无测试共用正式偏好、内容和 CLI；测试结果自动上传，失败不以跳过变成绿色。

### R05 · P2 · 服务意外停止后缺少完整恢复状态机

**源码确认，未杀死真实服务。** `NowPlayingController.swift:196` 只在初始化启动 adapter，未见子进程退出后的重启/退避；JSON 流 EOF 后不能依赖单元测试保证音乐会自行恢复。`AgentEventServer.swift:115` 收到 `.failed` 仅回调；`AgentBridge.swift:66` 在 server 非 nil 时拒绝再次 start，`isRunning` 也只看非 nil，可能出现对象仍在而服务已不可用的状态。

修复：区分 starting/ready/retrying/failed/stopped，带代次取消、指数退避和上限；外部服务恢复后自动重连，永久失败明确显示。停止功能后禁止定时器偷偷拉起服务。

验收：用假 adapter/listener 注入 EOF、退出码、启动失败、连续失败、恢复成功；状态不能假绿；关闭后无复活、重连不重复发送消息/回答审批。

### R06 · P2 · 重启的新旧实例有共享文件交接竞态

**源码推断，未在正式应用复现。** `MemoryUsageMonitor.swift:115` 创建新实例，收到启动结果后才终止旧实例；两个实例短时共用 AgentBridge 目录。旧实例 `AgentBridge.stop()` 无条件删除 port 文件，新实例的 `onReady` 也会写它，顺序未通过 owner/代次协议协调。新 port 先写时可能被旧实例随后删除。

修复：定义明确的重启交接顺序，或用 instance/lease 标识进行“仅移除自己仍拥有的文件”；新实例 ready 必须能被验证。共同编辑的文件也应有单实例/写入所有权边界。

验收：两个临时 bridge 实例按两种顺序交接，旧实例 stop 不得破坏新实例发现信息；重启期间新增内容、Timer/Agent 状态的去留有明确规定。

### R07 · P2 · 私有系统集成与 guardian 是持续维护成本

**架构确认 + 部分合成验证。** SkyLight/CGS、MediaRemote、CoreBrightness、IOReport/SMC、系统日志格式和 OSD 进程行为均有系统版本/硬件差异。guardian 修复了父进程退出恢复，但自身 SIGKILL、两者同时死亡仍不执行清理，已有 [ADR](decisions/001-system-hud-recovery.md) 明确这一边界。

修复方向：每个私有集成都要有能力检测、失败关闭、状态解释和独立开关。OSD 不能保证恢复时允许原生 HUD 共存；这是用视觉一致性换系统恢复可靠性的取舍。不要再堆一个同样可被杀死的 helper 后宣称彻底解决。

验收：实际支持的最老系统和当前系统、Intel/Apple Silicon（仅对确实要支持的平台）、真实亮度/音量、锁屏、休眠、异常退出。破坏性故障仅在独立测试账号/环境做。

### R08 · P2 · 编译器并发警告和一个 CF 所有权缺陷尚在

**源码/编译器确认；未跑 TSAN，不把警告直接等同于已发生的数据竞争。** Release 构建仍报告 AudioTap、Shelf、Calendar、锁屏回调等的 Sendable/actor 隔离警告。应按调用线程逐个确认，不批量加入 `@unchecked Sendable` 隐藏问题。

`KeyboardBrightnessSensor.swift:99` 将 `IORegistryEntryCreateCFProperty` 结果取成 `takeUnretainedValue()`，没有消费返回的 +1 所有权。Apple 说明由调用方释放，本机 SDK 头文件也一致；应改为正确的 retained 交接。实际泄漏量受 fallback 是否触发和 CF 对象实现影响，本轮没有测得 RSS 增量。[Apple IOKit 文档](https://developer.apple.com/documentation/iokit/1514293-ioregistryentrycreatecfproperty/)

验收：先覆盖 UI/回调交界和音频控制层的线程测试；分别执行 Thread Sanitizer、Address Sanitizer；音频 render 路径仍避免锁/分配，勿把 sanitizer 运行的 CPU 当性能基准。

### R09 · P2 · 测试产物、安装产物与显示版本无法一一对应

**文件元数据确认。** 本轮构建前 `/Applications/Atoll.app` 与本地 `Build/Release/Atoll.app` 的主二进制 SHA-256 不同，却同为 `1.0.0 / 1637`。近期 Stats 文档也记录“未安装”。因此本地测试通过不能自动解释安装版的卡顿；哈希不同本身不用于推断每项具体源码差异。

`Package.resolved` 已被 Git 跟踪，不能误报为缺失；但几个依赖使用 main 分支约束，CI 采用 `latest-stable` Xcode 且没有 `-disableAutomaticPackageResolution`，复现控制仍不够明确。

修复：测试/发布记录 source revision + dirty 标记/源码指纹 + 构建号 + Xcode + resolved hash + 产物 hash；固定日常 CI 工具链/解析版本，另设兼容性升级任务。保留安装前已知良好产物和回滚步骤。[Apple SwiftPM CI 指南](https://developer.apple.com/documentation/xcode/building-swift-packages-or-apps-that-use-them-in-continuous-integration-workflows)

验收：能回答“这份崩溃和 trace 对应哪个源码/二进制”；同一已验证产物进入安装验收，不在安装前临时重新解析依赖。本轮没有安装或改签正式应用。

### R10 · P2 · 内容可靠性和恢复范围需要明确

Extra Space 有一份 previous，Shelf 有错误保留，这些不是长期历史备份；Agent 草稿保存在内存，手动 Timer 的运行状态也没有持久化恢复路径。意外退出/更新重启后草稿、Timer 是否恢复，需要作为产品行为决定，不能用“全部自动保存”笼统描述。

运行数据仍分布在 Atoll 和旧 DynamicIsland 目录。下一步优先提供清晰的内容导出/恢复入口与位置说明，迁移时做版本与备份设计。无需为了一个便笺重写为数据库。

验收：只用合成文档完成损坏主文件、只读目录、上限、恢复旧版、重新启动；恢复不能无提示覆盖唯一残留。长文 100 KiB / 1 MiB / 5 MiB 测布局和撤销，不把 5 MiB 文件上限当作进程内存上限。

### R11 · P2 · 真实组合场景和长期资源曲线尚无证据

测试隔离会主动禁用真实服务；所以 311 个测试不能替代 AirPods 切换、多屏、网络卷、睡眠跨 Timer 到期、权限运行中被撤销等验收。RuntimePolicy 当前也只统一了部分模块，不是所有后台任务的总开关。Stats 磁盘详情的卷查询虽离开 UI，仍可能被异常挂载阻塞。

另需观察外部歌词/天气/封面响应大小、取消、缓存字节量和失败退避；已有数量上限不等于端到端内存预算。本轮没有进行超大真实网络响应实验，也未发现据此可宣称的远程攻击复现。

验收矩阵和资源指标见下文。对网络/磁盘故障用 fixture/独立测试卷，避免为测试影响真实数据。

### R12 · P3 · 高耦合大文件会提高修复回归成本

ContentView、SettingsView、MusicManager、BluetoothAudioManager 等集中很多职责。建议只在处理上述问题时抽出明确的持久化/进程/状态服务和可注入接口；不把本次稳定性工作扩成 UI 重做或全面架构迁移。

## 调试方法：固定现场 → 取证 → 最小复现 → 回归 → 真机复验

### 1. 每次先固定产物和功能组合

每份记录包含：bundle 路径与 hash、构建号/源码指纹、OS/硬件、显示器拓扑、供电/低电量模式、启用功能、操作步骤、发生时间。不要将 Debug、Release、已安装旧版的数据混在一张对比表里。

保留三个负载：轻量常驻；用户日常组合；最大组合（音乐/歌词/Stats/Timer/Agent/Shelf/Extra Space 并存）。每轮用相同输入和动作，预热后测量。插件协议只在用户实际使用且授权的真实集成环境补验，不为测试自行启动 CLI。

### 2. 按现象选择工具

| 现象 | 第一份证据 | 继续定位 |
| --- | --- | --- |
| 卡顿/卡死 | 精确时间、触发操作、进程 sample、Time Profiler + Hangs | UI 线程是在运行、等锁、等 I/O 还是反复刷新；SwiftUI/Hitches 看布局与帧 |
| CPU/耗电高 | 主进程和自有 helper 的 CPU time 增量、唤醒数、运行功能 | Time Profiler / System Trace；逐功能关闭做同负载对照 |
| 内存持续涨 | 预热后的 RSS/physical footprint 曲线、FD/任务/子进程数 | Allocations、Leaks、Memory Graph；按每次开关/重连看是否累积 |
| 数据未保存 | revision、保存起止/结果、dirty/error、目标目录可写性 | 临时目录故障注入，校验主文件/previous/recovery 的合成内容 |
| UI 有状态但功能失效 | 服务状态、最后成功时间、错误码、重试次数 | 假服务退出/超时/断线/重连回放，查代次与 owner |
| 偶发崩溃/跨线程异常 | crash report、对应 dSYM 和 build fingerprint | 单独开 ASAN / TSAN / Main Thread Checker，缩小触发序列 |

Apple 推荐通过 Instruments 的 Time Profiler/Hitches 等检查响应性，并用 sanitizer 发现测试时的内存和线程问题。工具运行有额外开销，性能基准用普通 Release 单独测。[响应性](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)、[运行时诊断](https://developer.apple.com/documentation/xcode/diagnosing-memory-thread-and-crash-issues-early)

卡住时先采样再重启，避免丢掉唯一证据。仅采集 Atoll 及明确属于它的 helper；不导出无关进程、用户正文或 Agent 凭据。不要以定时自动重启掩盖泄漏。

### 3. 让故障可重复

- 子进程：巨量 stdout/stderr、挂起、EOF、TERM 不响应、后代持有 pipe。
- 文件：拒绝写入、慢 I/O、损坏内容、容量边界、重启交接；比较内容 hash。
- 服务：启动失败、连接丢失、旧结果晚到、取消后回调、重复事件、重连后重复回复。
- 生命周期：启用→停用→启用 100 次，开详情→关详情，锁屏→解锁，睡眠→唤醒，多屏窗口创建→销毁。
- 权限：拒绝→授予、运行中撤销；UI 显示原因且可恢复，后台不能无限重试。

每修一个问题，先留下能失败的最小回归，再验证修复，最后在原来的完整操作里复测。

## 长期验收矩阵

| 阶段 | 操作 | 通过标准 |
| --- | --- | --- |
| 每次改动 | 确定性回归、原生单元测试、Debug/Release 构建 | 无未解释失败；源码/依赖/产物可对应 |
| 30–60 分钟真机 | 三组固定负载；Stats 详情、音乐、笔记编辑/撤销、Shelf 导入；权限失败 | 无崩溃/假成功/内容丢失；复现的卡顿有 trace 并解决 |
| 2 小时压力 | 反复切换/关闭 100 次；假服务退出和重连；临时故障卷 | 任务、FD、自有子进程数无按次数持续累积；退出失败可处理 |
| 24 小时日常 | 用户真实功能；合盖/唤醒、蓝牙路由、外接屏、断网 | 能自行恢复或明确提示；无静默数据丢失、服务假绿、OSD 残留 |
| 72 小时候选版本 | 固定 Release，跨日、长锁屏、重复连接变化 | 资源预热后趋于稳定；无新增 crash/hang；恢复/导出/回滚可用 |

建议先设以下工程预算，**它们是待同机基线校准的验收目标，不是本轮实测值，也不是 Apple 对所有功能的承诺**：

- 轻量关闭态、稳定无交互的 10 分钟平均 CPU 目标低于一个逻辑核的 1%；全功能另外定预算，统计包含自有 helper。
- 普通交互不出现主线程连续无响应 ≥250 ms 的 hang；动画另看帧/hitch，平均 CPU 低不代表不卡顿。Apple 的多数 hang 工具以超过 250 ms 为主要报告范围。[Apple hang 说明](https://developer.apple.com/documentation/xcode/understanding-hangs-in-your-app)
- 预热 15 分钟后，回到同样关闭态重复测 2 小时，RSS 增长先以 20 MiB 作为调查阈值；不把一次超过阈值直接定性为泄漏。结合 Allocations 的存活对象、physical footprint 和 24 小时趋势判断。
- 每 30–60 秒记录轻量资源样本，事件发生时另记状态；诊断文件轮转限额。崩溃、静默内容丢失、残留系统 HUD 暂停、重复发送/审批均为阻断项。

不要直接对正在使用的电脑自动断网、休眠、杀系统进程或填满磁盘来跑矩阵；需要这些操作的部分应在测试环境中安排。

## 建议实施顺序与完成定义

1. **先固定诊断和测试入口（R02、R04、R09）**：可靠日志导出、版本指纹、一键隔离回归。完成后故障可以定位、修复不依赖人工拼命令。
2. **再保护内容与控制阻塞（R01、R03、R06）**：退出保存协调、进程 deadline/排空、新旧实例交接。完成后失败不以无声丢数据或永久等待收场。
3. **补恢复和线程边界（R05、R07、R08、R10）**：服务状态机、降级、CF 所有权、重点并发检查，明确草稿/Timer 的恢复行为。
4. **跑固定 Release 的真机/soak（R11）**：把未验证项变成有日期、有产物、有结果的记录，再决定是否标记为稳定版本。

不在本轮建议加入新功能、定时自动重启、数据库重写、完整 Swift 6 迁移或 UI 重做。每一步都应产出可复现的缺陷/修复证据；需要的局部整理随修复进行。

本轮审查完成；报告中的修复、发行签名和长期真机验收尚未执行。
