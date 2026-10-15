# 当前版本测试与优化复核

日期：2026-10-15。范围：当前工作区源码的构建、全量原生单元测试、合成压力回归，以及已运行安装版的短时资源采样。

结论：Debug、Release 构建成功，通信和保存压力检查通过；**全量原生回归仍有 1 项失败，不能标记为全部通过**。最值得继续处理的是设置页检查的可靠性、音乐服务恢复入口，以及按实际显示需求减少后台更新。

本轮只新增测试记录，没有修改产品代码、偏好、用户内容或安装版。当前测试宿主与安装版的 `sourceSHA256` 均为 `8c2b6bb119509675e436f024e4808f631f2e64e58856639fdb7ea4131b7b18ad`。详细证据见[归档目录](audit/2026-10-15-current-review/README.md)。

## 实际执行结果

| 检查 | 结果 |
| --- | --- |
| Debug build-for-testing | 成功 |
| Release 增量构建 | 成功；未安装 |
| 全量 XCTest | 340 项：339 通过、1 失败、0 跳过 |
| 失败类独立复测 | 8 项：7 通过，同一项再次失败 |
| Python 隐私 / Timer 生命周期 | 7 项通过 |
| Agent / RPC 合成回归 | 17 组通过，包括 FIFO、取消、断连重连、拒绝 TERM 的自有子进程回收 |
| 插件队列 | 7 组合成场景通过 |
| Guardian / supervisor | 分别 4 / 3 个自建进程场景通过 |
| 当前源码资源探针 | UTF-8 整包 / 分块、取消完成、1 / 14 / 60 会话保存及重载通过 |

RPC 接收端停止读取时，150 ms 请求 deadline 实际约 **151 ms** 返回，MainActor 最大心跳间隔约 **13 ms**。60 个合成会话的保存提交约 **0.084 ms**，落盘文件约 **3.85 MiB**，60 个会话全部重载。这里测的是提交调用，不是完整写盘耗时。原生测试也覆盖了阻塞 writer 时只保留 active 与最新 pending 两份快照。

首次沙箱构建因 Xcode / SwiftPM 缓存目录权限失败；允许构建访问必要缓存后成功。原生失败使原有验证脚本提前停止，因此独立补跑其余 fixture，均通过。两个 xcresult 摘要的 `runtimeWarnings` 为空；原始日志仍有系统服务诊断。

本轮 Release 日志有 46 条 warning：45 条缺失预编译模块缓存路径，1 条未使用 AppIntents 的 metadata 提取提示。构建成功，但这些诊断需要与源码并发警告分开看；本轮没有清理构建目录或进行全面编译警告整改。

## 优先优化项

### 1. 设置页测试需要可靠的页面就绪与可访问性检查

位置：[LightweightPolicyTests.swift](../DynamicIslandTests/LightweightPolicyTests.swift:9)。全量和独立运行均在第 35 行失败，得到 `Labels: []`。测试创建完全透明的窗口，固定等待 100 / 200 ms，再通过 Objective-C selector 遍历可访问性树。

同次复测生成的[截图](audit/2026-10-15-current-review/settings-preview.png)明确显示了 Feature Management 内容及 “Preview lightweight suggestions”。因此，目前没有证据把这次失败直接解释为导航回退到了 General；可访问性读取为何为空仍未定位。下一步应先验证测试窗口的可访问性暴露与就绪条件，再保留真实导航断言；不能跳过断言来获得绿灯。

测试还把图片写到固定 `/tmp/atoll-feature-management.png`，并行运行会相互覆盖。后续应使用 XCTest attachment 或每次运行独立的路径。本轮归档图片的修改时间位于独立复测内。

### 2. 音乐服务应能从重试耗尽状态恢复

位置：[NowPlayingController.swift](../DynamicIsland/MediaControllers/NowPlayingController.swift:116)、[ServiceRetryPolicy.swift](../DynamicIsland/managers/Agents/ServiceRetryPolicy.swift:5)。连续失败在有限退避后进入 `unavailable`；未找到手动恢复或系统唤醒后开启新一轮有限重试的入口，`connectionStatus` 也未被界面消费。

建议提供显式重试，或在唤醒等明确事件后重置一次有限预算，保留关闭后不自动复活的约束。这是源码确认的恢复缺口；本轮没有让正式媒体服务连续崩溃。

### 3. 实时波形按可见消费者决定采集与刷新

位置：[AudioTap.swift](../DynamicIsland/audio/AudioTap.swift:159)、[启动控制](../DynamicIsland/DynamicIslandApp.swift:649)。启用开关和目标进程满足条件后启动采集，并建立 30 Hz 主线程平滑 timer；启动控制未统一关联播放、显示器状态与可见波形消费者。

建议用多个显示表面的实际需求共同决定启停，保留锁屏确实展示波形的情况。音量控制的 per-app tap 应保留自身需求。此项是潜在减负机会，没有测得它在本次用户配置中的独立 CPU 成本。

### 4. 录屏时长更新应局限在显示时长的小视图

位置：[ContentView.swift](../DynamicIsland/ContentView.swift:49)、[ScreenRecordingManager.swift](../DynamicIsland/managers/ScreenRecordingManager.swift:449)。根视图观察整个 recording manager，而 duration 每秒通过 `@Published` 更新；根视图使用的录屏布局只需要 `isRecording`。

建议拆开录屏状态与时长订阅，保留 tooltip 和实际时长展示所需的刷新。更新传播路径已确认，实际节能幅度尚未用 Instruments 测量。

## 资源采样与边界

只对既有 `/Applications/Atoll.app/Contents/MacOS/Atoll` 主进程 PID 842 采样，进程启动于 2026-10-13 18:29:44（本地时间）。未重新启动应用或改变功能组合。

| 主进程指标 | 本轮观察 |
| --- | --- |
| 3 分钟 / 36 个点的 RSS | 42.5–49.0 MiB，末值 48.4 MiB |
| `ps` CPU 点值 | 中位数 0%，峰值 5.7% |
| FD / 直接子进程 | 始终为 28 / 3 |
| 独立 120.09 秒累计 CPU | 增加 1.056 秒，折合单核平均 0.88% |
| 同段 physical footprint | 95.28–95.34 MiB，末值 95.30 MiB |

这段观察中 CPU 负担较低，footprint、FD 和直接子进程数量稳定，没有看到这些指标持续累积。RSS 小于 footprint 在此只作为不同计量口径分别记录，不据此推断压缩内存或缓存构成。

原始 3 分钟 CPU / RSS / FD / 直接子进程计数与独立 120 秒内核计数见[资源摘要](audit/2026-10-15-current-review/resource-summary.json)。`ps` CPU 是点值；累计 CPU 时间换算和 physical footprint 单列，不能把 RSS 与 footprint 混用。采样前段与本轮构建 / fixture 重叠，属于现有使用环境观察，不是受控空闲或能耗基准。指标只覆盖主进程，不代表完整进程树。

本轮未执行真实 Agent CLI、真实会话发送、XCUITest、ASAN / TSAN、睡眠唤醒、多屏切换或 24–72 小时持续验收。短时资源稳定不能证明长期无泄漏。当前仍待解决的可复现失败为上述设置页自动化检查。
