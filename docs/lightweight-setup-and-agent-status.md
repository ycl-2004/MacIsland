# 轻量功能管理与 Agent 状态修正

实施日期：2026-10-06。基于 `ce417b73631d1b59126496ca4d180ca756652c6d`。

这是[下一步审查](next-step-review-2026-10-06.md)的实施记录。继续使用原生
SwiftUI/AppKit、现有 Defaults 和 Agent 事件通道；没有新增依赖或重功能。
Terminal 留到以后评估。

## 使用入口

- **Settings → Feature Management**：位于核心设置，与 General、Appearance 同组。
  现有功能开关旁显示用途、后台行为、相关权限及详细设置入口。
- **Preview lightweight suggestions**：先列出当前开启、建议关闭的可选项；确认
  Apply 才修改。候选只有 Stats、实时波形、歌词、相机镜像、锁屏天气。
  基础音乐、Extra Space、Agents、Timer、Shelf 保持原选择。
- **Undo lightweight settings**：撤回本次预设仍未被手动改动的设置。之后手动
  开关过的项，即使又改回预设值，也不会被撤回覆盖。撤回信息可跨重启保留；
  不会在启动时自动应用轻量建议。预览期间设置发生变化时，需要重新确认更新后的列表。
- **Local storage and services**：只在打开页面或点击 Refresh 时读取已有计数。
  显示 Extra Space 文本、Shelf 缩略图缓存、网络缓存、Agent 卡片及连接情况；
  不启动常驻性能扫描，也不将缓存大小称为整个进程或单项功能的内存。
- **Settings → Utilities → Extra Space / Shortcuts → Open Extra Space**：配置
  直达快捷键，默认不占用组合键。启用功能时打开阅读页；功能关闭时打开其设置，
  不自动启用。快捷键受 Shortcuts 总开关控制。

关闭 Shelf 现在只隐藏并暂停导入和缩略图工作，内容保留；清空是 Shelf 设置里的独立操作，
原文件与正在交接的临时文件继续受保护。轻量建议仍保留用户的 Shelf 选择。

Extra Space 继续使用统一默认高度、内部滚动、双击编辑、⌘S 保存退出、保存后
上滑收起。直达快捷键不调用编辑器的焦点获取或进入编辑路径。粘贴、撤销、中文输入法、
存储失败与恢复语义见 [Extra Space](extra-space.md)。设置页也提供现有 tab 拖动排序、
会议链接、录屏隐藏等入口提示。

## Agent 提示的含义

| 观察到的情况 | 展示和行为 |
| --- | --- |
| 正在思考或处理工具 | 中性工作图标；普通工具调用不会变成待处理惊叹号 |
| 明确审批或问题尚未解决 | 保留待处理标记及请求数量；其他工具仍在运行时可以同时显示工作状态 |
| 本轮明确成功 | “This turn finished”，短暂提示一次；不是整个项目已完成的承诺 |
| 整轮失败 | 错误状态；工具执行失败本身不等于整轮失败 |
| 用户取消 | 中性停止状态，不显示成功提示 |
| 权威连接丢失或传输溢出 | 状态暂不可确认，显示最后观察；普通输入继续受保护，不宣称原终端已结束 |

连接异常使用灰色断开连接图标，与待审批的惊叹号分开。点击收起刘海的 Agent 提示，
会打开对应会话，而不是任意上次选中的卡片。

待处理请求立即阻止普通消息发送。收起刘海的紧急提示等待 250 ms 稳定窗口，避免
自动审批短暂闪烁；卡片的请求事实和输入保护不延迟。明确完成保留原来的 6 秒期限，
重复事件不延长。正在查看同一个会话时减少完成提示和边框动画，未解决请求仍有标记。

## 状态来源与兼容策略

健康的 Codex owner feed 提供会话内容与运行状态；hook 只能补宿主信息，不覆盖
实时审批。连接丢失保留最后事实并标为不确定，重连后的 owner 快照才用于重新确认。
订阅前先登记受保护的临时卡片，避免在 resume 回应前到达的审批丢失。

请求数量只计算已识别的请求，waiting 汇总状态不额外增加数量；仅有汇总状态时显示等待报告。
字符串 RPC ID 使用完整 SHA-256 摘要，保留字符串与数字命名空间，不截断后合并不同请求。
当前请求按 ID 跟踪，解决一个请求不会清除其他请求。普通工具完成不能解除待审批。
审批操作仅限 Atoll 发起的对应回合；外部终端的请求仅观察，不在 Atoll 代为回答。
审批 UI 还包含连接代次，旧界面不能回答重连后复用的 RPC ID。

使用可用的 turn/tool/request ID、最近结束的回合 ID、owner 发出时间及连接代次
拒绝可识别的旧事件；旧 hook 也不能释放或替换当前回复通道。旧协议没有 ID 或可靠
来源时间的事件仍可能无法完全判断乱序，不能把本机接收时间当作源事件顺序保证。
转录内容用于展示，不从最后一句话猜工作完成。

Claude Notification 只接受明确权限和问题类型，认证、完成、未知类型不升级为
用户请求。工具失败后恢复工作状态；中断与整轮失败各自处理。
**Settings → Agents** 的扩展生命周期选项默认关闭：

- Claude 扩展配置加入 `PostToolUseFailure` / `StopFailure`。
- Codex 扩展配置加入 `PostToolUse` / `Interrupt`。

用户应在确认所用版本支持后选择扩展配置，再点击 Install/Update。仅切换选项
不会自动改 Agent 配置。本轮没有调用真实 CLI 或读取安装版本；旧配置继续可用，
但未提供的事件无法凭空补齐。已有 hook/plugin 要通过设置页更新才使用新传输实现。

Pi 的 UI prompt API 没有原生请求 ID：插件在本次运行内按 kind/title 配对并生成
本地关联 token，不把它称为提供方的稳定身份。OpenCode 使用 permission/question
原生请求 ID；取消后 idle 不产生成功。Grok 采用已知类型的保守白名单，本轮没有获得
完整官方 schema，不能声明所有版本已验证。

## 后台工作与有界资源

共享运行策略先接入 Stats 与 Codex 连接刷新，不一次改所有 manager。锁屏、低电量
变化采用通知，页面可见性按窗口登记，没有增加轮询器。

| 状态 | Stats 最小采样间隔 | Codex 连接刷新间隔 |
| --- | --- | --- |
| 普通、可见 | 用户设定，至少 1 秒 | 会话展开 1 秒，否则 3 秒 |
| 普通、隐藏且允许后台采样 | 至少 5 秒 | 同上 |
| 低电量、可见 | 至少 3 秒 | 会话展开 3 秒，否则 10 秒 |
| 低电量、隐藏且允许后台采样 | 至少 10 秒 | 同上 |
| 锁屏 | 停止采样 | 15 秒 |

Stats 关闭功能或关闭最后一个可见面时按现有后台采样偏好暂停；冷启动隐藏状态
不会仅因后台选项而启动采样。多屏中的一面关闭不会停止另一可见面的采样。
锁屏前已运行且允许后台采样时，解锁会恢复采样。采样器保留发布出来的新策略，
避免 `@Published` 的 willSet 阶段回读旧状态而无法启动；直接启停回归先复现了该问题。
降低连接刷新频率不暂停已连接的 Agent 事件；Timer 到期、录音和主动操作不使用该门控。

Agent 卡片上限 60；每卡 40 条消息，每条 16,000 字符；当前请求最多 64 个，
已结束回合 ID 最多 16 个。快照上限 8 MiB。批量移除预算处理后只发布一次集合变化。

Pi/OpenCode 传输队列最多 64 项，普通活动占用最多 32 项并可合并；审批、问题、
结束等关键事件预留容量。单次只启动一个自有桥接子进程，2 秒未退出则终止；退出时
flush 等待最多 1.5 秒。payload 字段、文本与工具参数也有上限并复制为独立 JSON，
不让短队列保留提供方的巨大字符串对象。
管道错误会先终止自有子进程并等到退出再发送下一项；队列清空与 Promise 收尾之间
到达的新事件会继续排空，避免结束事件停留在无人处理的队列里。

关键事件仍超过上限时保留有界的不确定状态通知，在积压事件之后发送，避免又被旧
积压覆盖。它是有限容量的尽力传输，不保证桥接不可达、提供方强制退出或超出会话
容量时必达。被标记不确定的 hook-only 会话可能需要新回合或重新启动源来恢复可信状态。

## 验证与仍需现场确认的事项

测试数字、源码哈希、构建和截图见
[验证记录](audit/2026-10-06-lightweight-fixes/verification.json)。
Agent 验收使用 fake 客户端、隔离临时目录和测试进程；没有真实审批回复、真实会话、
用户剪贴板或 Agent 配置操作。原生测试覆盖设置路由、预设事务、运行策略和 Extra Space
已有输入/存储交互，但不是整机手势、权限与跨版本的现场验收。

本轮没有 10 分钟固定场景前后性能对照，也没有 24–72 小时含睡眠、多屏和断线的
持续运行数据。可以确认工作量有边界、隐藏状态降低采样，不能据此声称实际 CPU、
电量或长时间稳定性已经保证。下一次运行验收应使用同机 Release、固定设置分别测
空闲、音乐、Agent、大文本与拖放；记录 CPU time、footprint、唤醒、文件描述符与卡顿。

本地 Release 已作为验收产物生成；是否安装、提交或推送以交付记录为准。

## 主要语义依据

- [Claude hooks](https://code.claude.com/docs/en/hooks)：Notification、工具失败和 StopFailure 分开；Stop 只表明本轮响应结束。
- [Codex hooks](https://developers.openai.com/codex/hooks) 与 [app-server 协议](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/common.rs)：工具/回合身份、请求解决事件、可选 `emittedAtMs`。
- [Pi 扩展类型](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/src/core/extensions/types.ts)：prompt 配对事件没有 ID，settled 与模型回合不同。
- [OpenCode SDK 类型](https://github.com/anomalyco/opencode/blob/dev/packages/sdk/js/src/v2/gen/types.gen.ts)：permission/question 回应的 `requestID`。
- [ProcessInfo 低电量状态](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled)：事件触发的电源策略输入。

## 下一版跟进修正

详见 [下一版改进](next-version-fixes-2026-10-06.md)：tab 路由统一、Calendar 按需求查询与独立当日提醒、
Extra Space 查找/导出、当前权限与运行状态，以及系统减少动态效果支持。已有完整验证收据属于前一轮；
本轮证据另存，不改写先前测试结果。
