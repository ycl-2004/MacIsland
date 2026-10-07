# 下一版复核：把现有功能做准、做顺手

日期：2026-10-06（America/Vancouver）。基线：`ce417b73631d1b59126496ca4d180ca756652c6d` 加上上一轮尚未提交的轻量管理与 Agent 修正。

**建议下一版集中处理四件事：Agent 请求准确性、功能关闭语义、Calendar 后台查询、Extra Space 查找与导出。** 不再扩充独立模块。当前架构可以继续走轻量方向，但尚无安装后性能对比和长期运行数据，不能把“有上限、能暂停”直接等同于“已经证明不卡”。

后续：用户已授权落实全部八项，见 [下一版改进](next-version-fixes-2026-10-06.md)。以下保留实施前的诊断依据。

这是复核与实施建议。本轮未改产品源码、测试源码或用户设置，未安装、提交、推送，也未连接真实 Agent。源码检查与假客户端回放的结论分开记录。

## 发现与优先级

### N01 / P1：一次审批可能显示为两项待处理（隔离回放确认）

Codex RPC 请求会写入 `rpc:n:1`，线程状态又写入 `status:approval`。卡片直接使用整个 `pendingRequests.count`。

回放结果：发出一次审批，实际可操作审批为 1，卡片计算值为 2；普通输入仍被正确阻止。这里确认的是**数量展示错误**，不能据此认为应删除状态汇总或放开输入。

建议把“已识别的具体请求”与“来源报告仍在等待”分别建模或分别计算。已知请求显示准确数量；仅有汇总状态时显示“等待审批 / 回答”，不编造数量。多个实际请求必须独立保持。

依据：[状态投影](../DynamicIsland/managers/Agents/CodexSessionProjection.swift#L44)、[请求登记](../DynamicIsland/managers/Agents/AgentConversationService.swift#L753)、[卡片数量](../DynamicIsland/components/Agents/NotchAgentsView.swift#L194)、[回放](audit/2026-10-06-next-version-review/replay.json)。

验收：汇总先到或 RPC 先到均显示 1；两个实际请求显示 2；回答一个后保留另一个；未知数量不会显示为确定数字。

### N02 / P1：请求 ID 截断会合并不同审批（协议边界回放确认）

`requestKey` 将字符串 ID 截成前 240 个字符。发送两个长度 241、前 240 字符相同但末尾不同的请求后，只有一条待处理和一个审批入口。拒绝第一条之后，待处理归零，普通输入恢复；第二条仍没有收到回复。

这是隔离协议边界复现，**没有证明安装的 Codex 版本会产生这样的 ID**。若来源同时保留 waiting 汇总状态，输入保护可能仍然生效，但不同请求身份被合并的问题仍存在。

建议使用保留完整身份的有界键（例如完整 ID 的摘要并区分字符串/数字），或明确拒绝超限输入并保持状态不确定；不能截断后当作同一请求。保留 64 项请求上限、连接代次和回合保护。

依据：[键生成](../DynamicIsland/managers/Agents/AgentConversationService.swift#L747)、[回放](audit/2026-10-06-next-version-review/replay.json)。

验收：不同 ID 独立登记；回复一条不能删除另一条；整数 `1` 与字符串 `"1"` 仍不同；重复同一 ID 不重复弹出；边界拒绝不解除输入保护。

### N03 / P1：Shelf 的“关闭”同时清空托盘（源码确认）

关闭 Shelf 会调用 `removeAll()`，移除托盘条目并进入现有临时文件清理流程。这里不是删除用户原文件，但托盘状态不能靠重新开启恢复。上一轮轻量建议已排除 Shelf，管理页也已有警告；下一版应进一步统一产品行为。

建议将“关闭 / 隐藏”与“清空”分开：关闭停止拖放入口、缩略图等非必要工作，保留可恢复的托盘内容；清空作为独立明确动作。保留内容会占磁盘，需继续使用有界存储、显示占用，并保留拖放/分享/剪贴板租约保护，不能为省空间误删正在交接的文件。不增加无限历史。

依据：[关闭监听与清空](../DynamicIsland/components/Shelf/ViewModels/ShelfStateViewModel.swift#L95)、[管理页现有警告](../DynamicIsland/components/Settings/FeatureManagementSettings.swift#L43)。未切换真实开关或清空用户托盘。

验收：关闭再开启保留条目；关闭不继续生成缩略图；显式清空不删除原文件，不破坏正在交接的临时文件；重新启动后语义一致。

### N04 / P1：关闭当前功能后的 tab 回退不统一（源码控制流确认，原生交互待验收）

tab 有效性仅在 `onAppear` 校正。Extra Space 和 Timer 关闭时直接回到 Home，但 Home 可以因音乐、日历、镜像都关闭而隐藏。Stats、Agents、Shelf 未见同样的集中回退处理；内容区直接按 `currentView` 渲染。

建议集中维护可用 tab 列表。开关变化、快捷键、记住上次 tab、默认打开设置都使用同一个解析规则：当前项仍有效则保持；失效时按用户 tab 顺序选择可用项；全部关闭时显示小型设置入口。Color Picker 是右侧工具入口，应保留自己的可用性规则，不混入普通 tab 排序。

依据：[有效性检查](../DynamicIsland/components/Tabs/TabSelectionView.swift#L107)、[关闭回退](../DynamicIsland/DynamicIslandViewCoordinator.swift#L146)、[内容分派](../DynamicIsland/ContentView.swift#L1224)。这是源码路径结论，未在正在运行的应用中复现。

验收：刘海展开时关闭当前 tab、关闭隐藏 Home 下的 Extra Space、全部关闭、恢复上次 tab、使用快捷键，均不会停留在已禁用页面；重新开启保持保存的顺序。

### N05 / P1：Calendar 还有持续后台查询路径（源码确认，开销未测量）

`CalendarManager` 一旦初始化就启动每 60 秒循环。循环只检查日历访问权限，然后刷新锁屏事件，未检查显示需求、相关功能开关或当前锁屏状态。事件查询使用所有日历；如果用户选择 all-time，会查询至未来 365 天。相等比较只减少发布，不省掉这次查询。

已有 Stats / Codex 可见性策略是合适的方向，Calendar 可以作为下一接入模块：无消费者时暂停周期查询；显示时补刷新；EventKit 变化适度合并；锁屏日历仅在需要时更新。**会议提醒、到期计时和活动记录仍按自己的期限工作**，不能仅用 Home 隐藏或刘海收起关闭它们。锁屏视图本身已有部分锁屏感知逻辑，本条针对 manager 的独立查询循环。

依据：[初始化](../DynamicIsland/managers/CalendarManager.swift#L63)、[查询范围](../DynamicIsland/managers/CalendarManager.swift#L257)、[后台循环](../DynamicIsland/managers/CalendarManager.swift#L347)、[现有运行策略](../DynamicIsland/helpers/AtollRuntimePolicy.swift)。

验收：以注入服务计数验证隐藏、禁用、锁屏、重新显示和授权变化时的查询次数；同时验证会议提醒不漏。再用同机固定设置测唤醒与 CPU；本轮没有读用户日历，也没有测得实际耗电改善。

### N06 / P2：Extra Space 的下一步是找得到、带得走（入口缺失由源码确认）

已有连续文本、内部滚动、双击编辑、⌘S、原生撤销、保存恢复。当前没有专门的查找或文本导出入口，快捷键处理也没有显式接入 ⌘F。不能仅据此断言所有系统路径下 ⌘F 都失效，但 accessory 刘海窗口缺少常规菜单支持，值得补齐明确行为。

建议只增加当前文档的 ⌘F 查找和导出 `.txt`。查找在阅读模式可用，不为了查找进入编辑；长文本匹配避免阻塞主线程；导出以原生保存面板选位置，不加入笔记列表、云同步或剪贴板历史。保持当前默认高度。

小修：设置文案固定写“保存后上滑关闭”，实际支持反转方向或关闭手势，应按配置显示。

依据：[编辑快捷键](../DynamicIsland/components/ExtraSpace/ExtraSpaceTextView.swift#L48)、[工具栏](../DynamicIsland/components/Notch/NotchExtraSpaceView.swift#L91)、[手势实际配置](../DynamicIsland/components/ExtraSpace/ExtraSpaceEditor.swift#L132)、[设置说明](../DynamicIsland/components/Settings/ExtraSpaceSettings.swift#L37)。

官方能力参考：[NSTextView 查找栏](https://developer.apple.com/documentation/appkit/nstextview/usesfindbar)、[NSTextFinder 增量查找](https://developer.apple.com/documentation/appkit/nstextfinder/isincrementalsearchingenabled)、[NSSavePanel](https://developer.apple.com/documentation/appkit/nssavepanel)。最终接法仍需验证只读窗口焦点、查找取消和中文输入法。

验收：阅读模式查找与跳转、重复匹配、无结果、取消；不改变原文、撤销或编辑状态；大文本输入仍响应；导出取消无副作用，成功内容保持 Unicode 与换行。

### N07 / P2：功能管理可补“当前状态”（产品建议）

管理页目前有开关、用途、权限说明和全局资源计数；尚未逐项显示实际授权或运行状态。用户可能打开一个功能，却不知道为何没有生效。

建议逐步补“已开启 / 等待权限 / 按需待命 / 正在工作 / 连接不可确认”，先做有可靠已有状态来源的功能；提供进入对应设置的动作。开启开关不要立即弹出所有权限请求。事件驱动或打开页面时更新，不为状态页启动新的性能扫描，也不声称精确计算每个 SwiftUI 功能的内存。

依据：[当前管理页](../DynamicIsland/components/Settings/FeatureManagementSettings.swift)。

### N08 / P2：跟随系统减少动态效果（源码覆盖缺口）

Swift 源码未发现 `accessibilityReduceMotion` 接入。Agent 的提示边框是五次有限脉冲，工作图标有持续工作状态动画；没有证据证明它们造成了用户卡顿。

建议遵循系统 Reduce Motion：使用静态待处理标记，简化切换与脉冲，继续保留必须处理的信息。无需新增复杂动画设置系统。官方入口：[SwiftUI accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)。

### 维护建议：按改动抽取，不做全面重写

`SettingsView.swift` 当前 6,998 行，`ContentView.swift` 2,549 行。大文件本身不是运行慢的证明，但提高检查和修改成本。处理上述事项时逐步抽取 tab 规则、功能描述和页面；不在这版顺带重写所有 manager 或迁移整个并发模型。

## 推荐这版的范围

1. 先修 N01、N02：数字可信，请求身份准确，输入保护不提前解除。
2. 再做 N03、N04：所有功能开关具有可预测的数据和导航语义。
3. 接入 N05：减少没有消费者的日历查询，用查询次数和固定负载测量验证。
4. 加 N06：当前文档查找与纯文本导出；手势文案随设置变化。

N07、N08 作为随后的小批次。若时间有限，先交付前三步并现场验收，不为凑功能赶入新模块。

适合保留：基础音乐控制、Timer、Extra Space、按需 Shelf、确实在用的 Agents。Stats、实时波形、歌词、镜像、天气、下载观察按个人实际使用开启；提供选择即可，不强制统一关闭。Terminal 继续滞后；不增加无限剪贴板历史、完整 AI 工作区、插件商店或新复杂音频。

## 发布与性能判断

方案适合轻量长期运行的条件是：存储有上限，后台任务有需求门控，关闭功能真正停止非必要工作，关键事件不靠 UI 轮询，失败时可恢复。当前已有这些基础，Calendar 和 tab/关闭语义仍需补齐。

上一轮记录的 36 个原生测试、51 个状态场景、7 个插件队列场景、15 个 Agent 回归分组及 Release 构建是**上一轮的证据**，本轮没有重复运行完整套件。[上一轮收据](audit/2026-10-06-lightweight-fixes/verification.json)及[限制](audit/2026-10-06-lightweight-fixes/README.md)继续适用。本轮对 Swift 产品/测试文件做前后哈希比较，并单独编译真实 Agent 源码执行两类隔离复现。

发布前仍需：安装后的快捷键/鼠标/双指/焦点检查；实际支持的 Agent 版本与用户发起的 hook 更新；Agent 等待、Timer 到期、音乐/录音并存的交互；同机同设置 10 分钟固定负载比较；24–72 小时睡眠/唤醒、多显示器和重连验收。尚未完成这些检查，所以暂不宣称“长期使用已完全稳定”或具体节能比例。

本轮可重放证据：[审查收据](audit/2026-10-06-next-version-review/verification.json)、[假客户端源码](audit/2026-10-06-next-version-review/AgentReviewProbe.swift)、[编译及运行说明](audit/2026-10-06-next-version-review/README.md)。
