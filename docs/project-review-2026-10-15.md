# Atoll 当前项目审查

日期：2026-10-15。结论：当前工作区可以完成 Debug/Release 构建，但仍有两个已用合成数据复现的使用故障、一个源码确认的媒体恢复缺口，以及一个本机重复失败的测试验证问题。建议先修恢复保存与草稿容量，再补媒体重试入口和测试可靠性。

本轮审查当前工作区，包括已有未提交修改和新增源码。重点检查退出保存、内容恢复、计时器、Stats、Agent 通信和后台进程生命周期；不是对全部源码或全部功能组合的完整证明。没有修改业务源码、安装应用或调用真实 Agent CLI。

## 1. P1：恢复文件首次读取失败后，修复文件仍不能正常退出

**已复现。** `RecoveryFile.swift:26` 在读取失败时同时设置 `didLoad = true` 和 `loadFailure`。此后的 `save()` 在第 31 行直接抛出原错误，不重新读取文件。虽然显式调用 `load()` 可以清除错误，但 Agent 草稿和 Timer 的生产调用路径只在初始化时读取一次，没有向用户提供重新加载入口。

触发条件是启动时草稿或 Timer 恢复文件损坏，或第一次读取失败。用户修复磁盘上的文件、再按 Quit/Restart，仍会失败：退出协调器每次都要求草稿和 Timer 保存成功。对话框建议“解决存储问题后重试”，但同一实例没有完成这一操作的路径。

用当前未修改的 `RecoveryFile` 和 `AgentConversationService` 编译探针：先写入损坏 JSON，等初始化读取失败，再将文件修复为有效空字典。一个新 `RecoveryFile` 能正常读取修复结果，但旧对象仍拒绝保存；`AgentConversationService.saveForTermination()` 也继续返回错误。

```text
recovery_file_repaired_on_disk=true live_store_retry_rejected=true
draft_file_repaired_on_disk=true termination_save_still_rejected=true
```

位置：[RecoveryFile](../DynamicIsland/managers/Agents/RecoveryFile.swift)、[AgentConversationService](../DynamicIsland/managers/Agents/AgentConversationService.swift)、[TimerManager](../DynamicIsland/managers/TimerManager.swift)、[退出协调器](../DynamicIsland/managers/AppTerminationCoordinator.swift)。

修复方向：提供明确的恢复/重新加载操作；重试时验证当前文件，保留损坏前身和当前内存编辑，成功后解除错误状态。不能直接去掉损坏文件保护。验收应覆盖首次损坏、修复后重试、未保存编辑保留和正常退出。

## 2. P2：发送成功留下空草稿，累计 64 个会话后阻止新输入

**已复现。** `AgentConversationService.swift:524` 在发送成功后将草稿设为 `""`，第 473、664 行的其他发送路径也采用同样方式；但 `setDraft()` 第 129–130 行对字典条目计数，没有排除空值。保存到磁盘时才过滤空值，不会清理内存字典。

使用现有 `FakeCodexClient` 和当前生产服务，对 64 个不同合成会话逐个发送并等待成功，结果为：

```text
successful_sends=64 empty_draft_entries=64 new_session_input_blocked=true
persisted_empty_drafts=0 in_memory_slots_still_used=64
```

也就是说，实际已没有未发送草稿，第 65 个新会话仍提示草稿存储已满。会话有 60 个的独立内存上限，淘汰旧卡片也没有清除这些草稿条目。重启会从过滤后的文件加载，因此能临时解除空记录造成的限制，但正常运行不应依靠重启恢复输入。

位置：[AgentConversationService](../DynamicIsland/managers/Agents/AgentConversationService.swift)。

修复方向：成功发送且草稿未被用户继续编辑时删除对应键，统一清空语义；容量只统计真实非空草稿。增加跨超过 64 个不同会话成功发送的测试，并保留“发送期间的新编辑不能被清空”的保护。

## 3. P2：音乐 adapter 耗尽重试后，没有恢复入口

**源码确认，未对真实媒体进程注入故障。** `NowPlayingController.swift:122–124` 在六次有限重试耗尽后进入 `unavailable`，不再安排任务。初始化方法为私有，控制器没有用户重试或唤醒后重新开启有限预算的入口。`MusicManager` 只在初始化时创建控制器，也未订阅 `connectionStatus` 来展示故障或提供恢复操作。

因此 adapter 连续失败后，即使外部条件恢复，当前控制器也不会再次连接。播放状态被设为暂停，用户未必能辨别是音乐停止还是后台服务已失效。这也是 2026-10-10 背景审查记录中尚未消除的缺口。

位置：[NowPlayingController](../DynamicIsland/MediaControllers/NowPlayingController.swift)、[ServiceRetryPolicy](../DynamicIsland/managers/Agents/ServiceRetryPolicy.swift)、[MusicManager](../DynamicIsland/managers/MusicManager.swift)。

修复方向：保留有界退避，增加明确的手动重试，并可在系统唤醒等事件上重新开启一次有限预算；将不可用状态接入界面。用假 adapter 覆盖连续失败、预算耗尽、条件恢复和用户重试。

## 4. P2：设置页测试出现可重复的错误失败判定

**本机重复验证。** 全量原生测试为 339 通过、1 失败、0 跳过；单独复跑 `LightweightPolicyTests` 为 7 通过、同一项失败。失败项是 `testFeatureManagementDestinationRendersInTheSettingsWindow()`，报告读取到 `Labels: []`，于是断言未进入功能管理页。

但该测试随后生成的截图中清楚显示了目标按钮 `Preview lightweight suggestions` 和功能列表，说明此次页面路由实际成功。失败反映的是该测试当前的无障碍树获取/断言方式，不能据此判断功能管理入口坏了。测试使用透明 NSPanel、固定等待时间和直接递归访问无障碍对象；本轮未确定哪个环节导致空树。

位置：[LightweightPolicyTests.swift:9](../DynamicIslandTests/LightweightPolicyTests.swift)、[本轮截图](audit/2026-10-15-project-review/feature-management.png)。

修复方向：分别验证目标路由状态和真实渲染，再为无障碍树建立可靠的宿主与等待条件。保持有效断言，不能简单跳过此测试。本机环境是 Xcode 27.0 / macOS 27.0.1；没有据此推定固定在其他工具链上的远端 CI 也失败。

## 本轮验证与证据

| 检查 | 本轮结果 |
| --- | --- |
| Debug build-for-testing | 通过 |
| Release build | 通过 |
| 原生 XCTest 全量 | 339 通过，1 失败，0 跳过 |
| LightweightPolicyTests 单独复跑 | 7 通过，1 失败，0 跳过 |
| Python 隐私/Timer 检查 | 7 通过 |
| Agent/RPC 合成回归 | 17 组 PASS，包含慢读写、取消和 owned child 清理 |
| 插件队列合成回归 | 7 组通过，未启动真实子进程 |
| Process supervisor / 历史 guardian fixture | 3 / 4 组通过，仅操作测试拥有的进程 |
| 新增缺陷探针 | 两个问题均复现，退出状态 0 表示故障条件断言成立 |

构建源码 SHA-256：`8c2b6bb119509675e436f024e4808f631f2e64e58856639fdb7ea4131b7b18ad`，commit 为 `b6a518d9`，工作区有未提交修改。没有把本轮构建结果当作安装版运行结果。

第一次受限沙箱构建因 Xcode/SwiftPM 缓存不可写而失败；允许访问编译缓存后的隔离构建成功。原生测试失败使现有一键验证入口提前结束，后续合成检查和 Release 构建已在本轮分别执行。

- [可分享的结果摘要](audit/2026-10-15-project-review/results.json)
- [缺陷探针](audit/2026-10-15-project-review/ReviewProbe.swift)（复用现有回归文件中的假客户端和终端）
- 本地完整日志：`Build/VerificationRuns/project-review-20261015-full/`、`project-review-20261015-settings/`、`project-review-20261015-probes/`

未执行修复、ASAN/TSAN、24–72 小时连续运行、真实 Agent 交互或跨系统/硬件验收。现有用例通过说明已有覆盖有效，但两个新增探针表明恢复与累计容量边界仍需补齐。
