# Atoll 后台负载与长期运行复核

日期：2026-10-10。检查范围：`ce417b73..b6a518d9`（上一个 commit）及当前全部未提交改动，包括未跟踪的 Swift/C 源码。结论：现有架构和常态资源占用支持“偏轻量”的判断；仍有可复现的通信阻塞、慢存储排队问题，不应直接标记为已通过全天稳定性验收。

本轮仅新增审查记录和隔离探针，没有修改产品代码、用户偏好或安装版，也没有启动真实 Agent CLI。既有稳定性文档中的历史测试结果不当成本轮新结果。

后续：用户已要求修复 R1/R2，实施和新验证见 [背压修复记录](background-backpressure-fixes-2026-10-10.md)。本文的故障数字及安装版指纹保留为修复前证据。

## 要求与范围

1. 检查上一个 commit 的后台运行影响。
2. 检查当前已修改和新增源码。
3. 判断当前 CPU、内存、句柄、后台进程负担。
4. 检查长时间运行、取消、恢复和资源生命周期风险。
5. 给出有证据、按优先级排序的优化建议。

重点覆盖：功能/运行策略、Stats、Calendar、音频 tap、媒体 adapter、录屏、Focus、Timer、Agent 传输/缓存/持久化、Extra Space/Shelf、退出保存、日志和验证工具。本轮不是对全部历史源码逐行证明，也不覆盖全部外部 Agent 协议版本。

## 已复现的问题

### R1 · P1 · Agent 管道写入能阻塞 MainActor，使请求超时失效

位置：`DynamicIsland/managers/Agents/CodexRPCClient.swift:157–181`；输入限制见 `AgentConversationService.swift:128–141,452`。该路径早于最新稳定性改动存在，当前仍未消除。

`CodexRPCClient` 隔离在 MainActor，发送请求时同步执行 `FileHandle.write(contentsOf:)`。请求超时也运行在 MainActor。当接收端暂停读取、有效载荷超过管道可用空间时，写调用阻塞，计时任务不能按时运行。

用**未经修改的当前 RPC client 和 framing 源码**编译独立探针，替代端只做 JSONL 握手，并在握手后暂停读取 3 秒，不调用任何真实 CLI：

| 合成输入 | 请求 timeout | 实际完成时间 | 最大 MainActor 心跳间隔 |
| --- | ---: | ---: | ---: |
| 16,000 个普通 emoji，64,000 UTF-8 bytes | 150 ms | 162 ms，返回超时 | 15.7 ms |
| 2,621 个家庭 emoji，65,525 UTF-8 bytes | 150 ms | 3,000 ms，返回成功 | 3,012 ms |

第二份输入同时满足现有 `String.count <= 16_000` 和草稿 `utf8.count <= 65_536` 限制。RPC JSON 封装后超过 64 KiB。它是边界压力输入；不能推断日常短消息必然卡顿，但证明现有 timeout 不是写入超时。持续停止读取可能延长阻塞。初次 400,000 bytes 实验超过草稿限制，已明确排除，保留记录作为审查纠错轨迹。

建议：将传输写入从 MainActor 移走，建立有字节上限的串行发送队列，并明确取消/写入 deadline 和断连行为；预算针对序列化后的完整数据及待写队列，保留已有草稿字节限制。不能只把同步 write 包进继承 MainActor 的 `Task {}`。超时后的 prompt 不自动重发，保留现有不确定交付语义。

验收：有效上限内长消息、多个会话发送、对端不读/中途退出、取消/关闭时，MainActor 心跳正常；队列有界；owned child 最终回收。探针：[代码](audit/2026-10-10-background-review/rpc-backpressure-probe.py)、[结果](audit/2026-10-10-background-review/rpc-probes.json)。

### R2 · P2 · 慢写入时，保存快照仍可积压

位置：`AgentSessionStore.swift:268–285`、`ExtraSpaceStore.swift:47–60` 和 `:65–78`。这是正常写入之外的资源边界，退出协调器的单次保存保护不覆盖持续自动保存。

- Agent：500 ms 节流只限制提交频率，没有限制 persistence queue 的待写数量。阻塞第一次写入后，以 550 ms 间隔产生 12 次更新；释放阻塞后，实际共写入 **13 份**快照。
- Extra Space：每次编辑都创建捕获完整文本的 work item。`cancel()` 可以跳过旧写入，但旧快照不会立即释放。阻塞第一次写入后产生 48 份约 1 MiB 的不同文本，RSS 从 12,255,232 bytes 增至 64,765,952 bytes，增加 **50.1 MiB**；释放后确实只有首尾两次写入执行。

探针沿用当前两个 store 的调度代码，只在临时副本的 `PrivateContentFile.write` 入口加入受控等待；所有内容均为合成数据。它模拟存储迟滞，**没有证明当前安装版在正常磁盘条件下发生泄漏**。

Apple 明确说明，取消 work item 后其资源的释放会延迟到下一次尝试执行或已开始的执行完成。这与上述观察一致。[DispatchWorkItem.cancel](https://developer.apple.com/documentation/dispatch/dispatchworkitem/cancel%28%29?changes=_1)

建议：每个 store 保留“一个进行中的写入 + 一个可替换的最新快照”，统一自动保存、Save Now 和退出 barrier；在提交到磁盘队列之前合并旧 revision。Shelf 的取消 work-item 保存也应按相同边界复核，不能只减少成功写入次数。

验收：阻塞 writer 后连续编辑/更新数百次，待保存快照与内存保持有界；解除阻塞后保存最新 revision，失败仍保留最新内存内容。探针：[代码](audit/2026-10-10-background-review/slow-save-probe.py)、[结果](audit/2026-10-10-background-review/slow-save-result.log)。

### R3 · P2 · 媒体 adapter 的恢复预算耗尽后没有恢复入口

位置：`NowPlayingController.swift:116–131`、`ServiceRetryPolicy.swift:7–23`。这是最新未提交稳定性改动引入的取舍。

连续失败按 1、2、4、8、16、30 秒退避，预算耗尽后进入 `unavailable` 并停止。源码中没有为这个 controller 提供唤醒/媒体应用重启/手动重试的重新启动入口；`connectionStatus` 也未接入用户界面。服务恢复后该 controller 会继续失效，通常需要重建 controller 或重启 Atoll。

限制重试能避免不断崩溃重启，但需要可恢复的熔断状态。建议增加明确的重试入口，或在系统唤醒/用户重试等事件上开启一次新的有限预算，不恢复短周期无限重试。AgentBridge 也有预算耗尽状态，目前可通过功能开关 stop/start 恢复。

这是源码确认的恢复缺口，未故意让安装版 adapter 反复崩溃。现有重试策略单元测试通过，仅证明策略符合当前设定。

## 可以进一步减负的点

### 音频实时波形按实际可见需求启停

`AudioTap.swift:160` 只按 `enableRealTimeWaveform` 判断启动，`:269` 创建 30 Hz 主线程平滑 timer。`DynamicIslandApp.swift:649–668` 在启动/功能开关时控制捕获，没有按暂停、锁屏、显示器休眠或没有可见波形统一停止。设置打开且目标进程存在时，可以没有可见消费者仍保留采集和 timer。

建议统一 waveform demand：播放状态、可见消费者、显示器状态共同决定；按多个显示器累计消费者，保留锁屏确实需要显示的情况。不要把控制音量所需的 per-app tap 一并停掉。目前该设置默认关闭，本次用户偏好没有覆盖，因此不是本次常态负载的已确认来源。

### 录屏红点仍连着整棵视图的每秒更新

`ScreenRecordingManager.swift:188,454–478` 每秒更新 `@Published recordingDuration`；根 `ContentView.swift:49` 观察整个对象。新设计关闭时只显示红点，时长主要供 tooltip/辅助功能使用，但录屏期间根视图仍会收到每秒一次的变化通知。

建议分离低频录屏状态与时长展示，让真正显示时长的小视图负责时钟；不要每秒使整个 notch 根视图失效。这里确认的是更新路径，未用 Instruments 量化这项优化可以节约多少 CPU。

### 非关键维护 timer 增加容差

Stats timer、Bluetooth 3 秒 fallback、AgentSessionStore 60 秒清理没有显式 tolerance；系统允许时可以合并唤醒。先减少无用定时器，再给剩余非关键 timer 合理容差，保留 Timer 到期和用户交互响应。[Apple：减少 timer 使用和设置容差](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)

## 应保留的已有改进

- 原生 SwiftUI/AppKit 架构；实时波形、Stats、相机镜像等默认关闭，轻量预设可逆。
- Stats 默认关闭 notch 后停止；锁屏停止、低电量降频、详情按需采集、后台串行采样、请求合并和旧 generation 丢弃；历史 30 点有界。
- Calendar 按需求查询；Shelf 缩略图有数量/字节/并发约束；Extra Space 有文件大小和 undo 历史限制。
- Agent session 数量/内容长度、HTTP 请求体、媒体 JSON 行和网络响应均有显式预算。
- 多数子进程已使用双流排空、取消和 deadline；媒体 supervisor 等待内核事件，健康时没有周期轮询。
- 移除了 OSD 系统进程暂停及持续检查；内存监控由系统压力事件触发；关键错误日志有隐私处理与限频。
- 普通退出与重启使用统一保存 gate，保存失败时保留内容。它解决数据保护的一部分问题，但不自动解决 R2 的运行中排队。

## 本轮验证

当前产品源码指纹为 `d270a8f0877de24a12af34a55f4586d9f044a14487c3d02a6dc6faeeb28ac7fd`，与 `/Applications/Atoll.app` 内 Release BuildInfo 相同；安装二进制 SHA-256 为 `88c588b72fb12d79626a65c38b2f03fd218f5289d3ebe4a21ba718552dc62840`。采样对象为 PID 71861，依据既有安装回执的启动 PID 与本轮进程启动时间连续性关联到该安装版；本轮 `ps` 输出中的路径被截断。补充的 `proc_pidpath` 完整路径读取因自动审批额度耗尽未执行，因此没有将其计为独立身份验证。新增审查文档/探针在 docs 下，不改变上述产品源码指纹。

本轮执行 `python3 Tools/verify-stability.py --output Build/VerificationRuns/background-audit-20261010`：Debug build-for-testing 成功；原生测试 **334 通过，0 失败、0 跳过**；Python 7、Agent/RPC 合成回归 16 组、插件 7 组、旧 guardian 4、owned supervisor 3 均通过。原生 xcresult runtimeWarnings 为空；不等于编译器和全部原始日志都没有警告。

Release 使用已安装、指纹相同的现成产物做资源采样。本轮没有重新执行 Release build、ASAN、TSAN、XCUITest、Instruments 或 24–72 小时 soak。两个新增故障探针揭示了现有通过用例没有覆盖的边界。

完整本地原始输出：`Build/VerificationRuns/background-audit-*`。可分享摘要和探针：[审查证据目录](audit/2026-10-10-background-review/README.md)。

## 后台资源测量

见证据目录中的 `runtime-summary.json`：包含主进程 12 分钟采样，以及单独的、按本机 Mach timebase 换算的累计 CPU/footprint/wakeup 采样。场景是用户现有功能组合、notch 关闭，Agent 活动可见；没有为了制造低占用而关闭用户的功能。开始阶段与隔离回归/构建重叠，不能当成严格空闲基准或电池续航测试。

| 指标 | 本轮观察 |
| --- | --- |
| 主进程 RSS，12 分钟 / 144 个点 | 72.5–108.2 MiB，最后 91.7 MiB；有回落，未见单调持续上涨 |
| 主进程 physical footprint，独立 120 秒采样 | 55.4–69.2 MiB，最后 57.1 MiB |
| 主进程 CPU | 12 分钟 `ps` 点值中位数 1.0%、均值 2.19%、峰值 31.9%；独立 120 秒累计 CPU 时间换算为单核 2.67% |
| 主进程 FD / 直接子进程数 | FD 在 27–28 间，直接子进程保持 3 个 |
| 已识别辅助进程的 footprint | supervisor 1.2 MiB，mediaremote Perl 8.0 MiB，log 3.5 MiB；不是完整进程树汇总 |

因此：内存常态较轻，后台 CPU/唤醒仍有优化空间；没有看到这段时间内资源数量不断扩张。短时间内 RSS 回落不能证明不存在缓慢泄漏。

RSS 与 physical footprint 口径不同，不能混用；`ps %cpu` 的采样摘要也不是精确 CPU time 增量。已知 helper 的统计单列，不把主进程指标冒充全进程树或系统级能耗。

## 接下来的最小验收

优先修 R1、R2，再补 R3 的恢复入口；不需要为了“轻量”更换架构。之后选定同一份 Release，完成 24 小时、再到 72 小时采样，期间覆盖日常功能开关、Stats 开关、音乐暂停/恢复、睡眠/唤醒和多屏切换。比较回到相同空闲状态后的 CPU、footprint、FD 和 owned children 是否回落，异常时保留同一产物的 Instruments trace。

当前证据支持继续日常使用和针对性优化；尚不能支持“长时间全部组合已验证、绝无泄漏或卡顿”的结论。
