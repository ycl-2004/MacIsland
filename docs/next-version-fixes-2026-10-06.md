# 下一版改进

日期：2026-10-06。落实[复核报告](next-version-review-2026-10-06.md)的 N01–N08，保留之前尚未提交的改动。Terminal 和重功能不在这次范围内。

| 项目 | 现在的行为 |
| --- | --- |
| N01 请求数量 | 具体请求与 waiting 汇总分开计算。一项审批不显示为两项；只有汇总时不编造数量。汇总状态仍保护普通输入。 |
| N02 请求身份 | 完整字符串 ID 使用 SHA-256 有界键，数字另用命名空间。重复 ID 去重；不同长 ID 分别保留。 |
| N03 Shelf | 关闭保留内容，取消导入和缩略图，阻止新的缩略图工作；设置提供独立 Clear。重开与重启可恢复。原文件、租约及交接保护保持原规则。 |
| N04 导航 | 可用 tab 的集中规则用于当前页、默认/快捷键目标、记住的页面、tab 列表和宽度计数。失效时按保存顺序回退；全部关闭显示设置入口。Color Picker 保留独立工具身份。 |
| N05 Calendar | 无需求或读权限时停止周期查询。可见 Home 更新选中日期；锁屏日历仅在需要时查询。提醒使用独立当天快照，跨午夜更新，不受 Home 浏览其他日期影响。 |
| N06 Extra Space | 原生 Find / ⌘F、匹配导航、`.txt` Export；不自动进入编辑、不加高默认窗口。关闭说明跟随手势开关和方向。 |
| N07 功能状态 | 显示现有文本保存、计时运行/暂停、Stats 采样、Codex 连接、相机运行及已知权限。未知状态明确指向 Details，避免把“已启用”说成“正在工作”。 |
| N08 动画 | 跟随系统 Reduce Motion，取消刘海/tab 移动、Agent symbol 动效、提示边框脉冲和 Core Animation 脉冲；保留静态待处理/录音标记。 |

## 存储和后台策略

Shelf 保留仍受已有 200 条、4 MiB 文本（单条 1 MiB）及文件副本预算约束；不增加无限历史。隐藏会保留磁盘内容，因此 Clear 是明确的独立操作。关闭前尚未完成的导入被取消，已有条目仍能恢复。关闭与清空采用不同代次，避免加载期间误丢或复活内容。

Calendar 共享锁屏、低电量、多窗口可见性信号。活跃消费者每 60 秒刷新，低电量时 120 秒；既有 EventKit 变化节流仍在。隐藏变更留到下一次显示/提醒需求处理。明确的日历页面操作可以按需取一次数据；关闭刘海不再触发选中日期查询。提醒的到期调度、Timer、录音与 Agent 事件没有套用显示门控。

Reminder 的数据源改为当前日快照；Home 仍有自己的选中日期数据。当前日已查询且仍新鲜时复用，否则单独查询；不每分钟同时查询无需求的两个页面。勾选完成同步刷新提醒快照，避免短暂显示旧状态。查询排队时取消会在真正读取前复查，返回后也避免发布已取消的结果。

功能管理只订阅已经存在的低频状态，去掉重复值；权限仅在页面打开、回到应用或手动刷新时读取。没有新的常驻状态扫描，也没有管理页自动权限请求。锁屏 widget 只读取已有日历授权；用户仍通过 Calendar 详细设置请求新授权。

## Extra Space 操作

- Find 或 ⌘F 在阅读模式也可打开。原生匹配栏在文本区域内占用空间，不改变刘海高度。
- 文本 view 为 responder 时，⌘G / ⌘⇧G 可前后查找；查找栏自身也有导航按钮。Escape 先隐藏查找栏。
- Export 选择 `.txt` 目标，后台原子写入当前已提交文本的 UTF-8 快照。取消不写入，错误保留可读提示，不修改原文与撤销。
- 查找或导出期间抑制自动关闭；退出、完成或页面拆除后释放。明确的关闭动作仍可使用。
- 双击编辑、⌘S、Undo/Redo、中文输入法、保存恢复与阅读上滑关闭沿用现有路径。

原生 API 依据：[NSTextView 查找栏](https://developer.apple.com/documentation/appkit/nstextview/usesfindbar)、[NSTextFinder](https://developer.apple.com/documentation/appkit/nstextfinder)、[NSSavePanel](https://developer.apple.com/documentation/appkit/nssavepanel)、[SwiftUI Reduce Motion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)、[EventKit 变更通知](https://developer.apple.com/documentation/eventkit/ekeventstorechangednotification)。当前项目 Swift 5 模式，主应用最低 macOS 14.6；现有 Defaults 9.0.3 保持不变。没有新依赖。

## 验证与限制

本轮测试、构建、源码哈希和可重放说明见[证据目录](audit/2026-10-06-next-version-fixes/README.md)。审查时的两类缺口已转为成功断言；原审查与上一轮收据保留历史，不改写失败记录。

本地验证：68 个原生测试、16 组 Agent 回归、51 个 Agent 状态案例通过，签名 Release 构建和 deep/strict 签名检查通过。导航集成测试曾发现本轮 `@Published` setter 的重复写回，已加入差值判断修正；失败与成功证据均保留。

原生测试验证查找栏真实打开/隐藏、只读文档与撤销不变、导出内容/失败、真实 Core Animation 脉冲移除、Shelf 保存恢复、Calendar 查询次数及跨午夜日数据。它们不等同于现场鼠标/双指、查找所有匹配/焦点、保存面板取消/错误展示或真实权限授权流程的端到端验收。

仍需现场：实际 Agent 版本和用户发起的 hook 更新，安装后全局快捷键/焦点/双指手势及导出面板，音乐/Agent/Timer/录音同时工作，同机同设置负载比较，以及 24–72 小时睡眠、多显示器和重连。没有实际耗电或 CPU 改善百分比，不能宣称长期运行已完全验收。

最初验证时构建结果保留在工作区，未安装或提交/推送。随后用户明确授权替换正在运行的应用，最新版已安装到 `/Applications/Atoll.app` 并重新启动；旧版保留在工作区备份。见[安装记录](audit/2026-10-06-next-version-fixes/installation.json)。本次仍未提交或推送。
