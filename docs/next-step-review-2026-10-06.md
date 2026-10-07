# 下一步核实：Agent 提示、功能管理与快捷交互

基线：`ce417b73631d1b59126496ca4d180ca756652c6d`，2026-10-06。

后续：用户已授权实施，见[轻量管理与 Agent 状态修正](lightweight-setup-and-agent-status.md)。
下文保留实施前审查结果；`AgentStateAudit` 当前版本已改为验收程序，有 GAP 会失败退出。

**结论：先修 Agent 状态与提示，再做功能选择清单和快捷入口。当前已有可复现的状态缺口，不能保证所有惊叹号都正确。继续沿用原生界面和现有事件通道，不增加重功能。**

本轮完成源码核实、官方事件语义对照、隔离回放与实施方案。未实现下面的产品改动，未替换正在运行的应用，也未提交或推送本轮文件。

## 本轮要求与完成依据

1. 完整给出下一步及顺序：见分阶段方案。
2. 评估可选轻量功能清单：见功能管理方案及 Shelf 数据约束。
3. 评估现有功能如何更顺手：见快捷入口、焦点和 Extra Space 方案。
4. 核实 Agent 正在工作时的提示：见来源检查与 28 个合成场景回放。
5. 运行现有检查并记录失败：回归 15 个分组中 14 通过，1 失败，见证据。
6. 保持产品边界与验证诚实：不做无限剪贴板历史、完整 AI 工作区、插件商店、新增复杂音频；Terminal 后期再评估。没有运行真实 Agent 或读取真实会话。

## 惊叹号首先要区分含义

- 会话卡片、Agents tab 标记和收起刘海状态：来自 `needsAttention`。
- Sessions 标题旁的惊叹号：来自 Codex 的 `connectionMessage`，可能是连接问题，并不代表某个 Agent 等待审批。
- 工具调用有自己的命令、编辑、读取等图标；普通 `PreToolUse` 本身不会变成惊叹号。

依据：[状态展示](../DynamicIsland/components/Agents/AgentStatePresentation.swift)、[卡片与连接提示](../DynamicIsland/components/Agents/NotchAgentsView.swift)、[tab 标记](../DynamicIsland/components/Tabs/TabSelectionView.swift)、[刘海选取规则](../DynamicIsland/managers/Agents/AgentSessionStore.swift#L171)。

目前主要是刘海状态展示，不应将每次图标切换都描述为系统通知弹窗。本轮没有现场复现用户看到的某一次通知；下列是实际源码上的合成事件回放，能证明实现缺口，不能直接确定那一次的来源。

**“仍在工作”与“需要你处理”可以同时成立。** 并行工具之一在运行，另一个等待审批时，提醒是合理的。方案应同时表达工作状态与待处理请求，不能用“正在运行就隐藏所有惊叹号”的规则。

## 已验证的缺口

| 编号 / 优先级 | 观察结果 | 用户影响与修正方向 |
| --- | --- | --- |
| A01 / P0 | Claude 仅过滤 `idle_prompt`；认证成功、完成类和未知 Notification 都映射为 `needsAttention` | 普通信息可能变成紧急提示。按明确类型白名单分类；未知类型不自动升级为审批 |
| A02 / P0 | Codex 缺少 `PostToolUse`；Claude 缺少工具失败及 `StopFailure` 映射 | hook-only 路径可能停留在上一状态。按适配版本补齐工具结束、失败和中断；工具失败不等于整轮失败 |
| A03 / P0 | Codex 的另一项 `item/completed` 会把待审批改成 thinking；两个审批回答一个后，仍剩一个请求，状态却变 thinking | 漏报，且影响输入保护。待处理请求按 ID 保留，普通工具事件不能清除它；剩余请求未解决前保持提醒和发送限制 |
| A04 / P0 | 旧回合完成事件能将新回合标 finished；hook reducer 也接受过时事件覆盖 | 完成与等待状态会倒退。保留 turn/tool/request ID、连接代次与来源优先级；过滤能识别的旧事件，无法确定时显示不确定 |
| A05 / P1 | `dropLiveFeeds()` 后原来的等待仍被当作在线等待 | 连接丢失后提示没有可信度标识。改为“状态暂不可确认”，保留最后观察；不能据此宣称会话结束或解除输入保护 |
| A06 / P1 | 重复完成更新 `finishedAt`；Grok 取消映射为完成；Codex interrupted 虽为 idle，却仍有 6 秒高优先级 highlight | 重复或取消事件抢占刘海。完成只认一次；取消与成功分开；普通 idle 不推断工作成功 |
| A07 / P1 | Pi/OpenCode 的公共发送队列已有 32 项时，后来的 `session.deleted` 被直接丢弃 | 可能漏掉关键最终状态。保持队列上限，合并普通活动，保留按会话的关键状态；溢出时降为不确定，适用来源用现有刷新恢复 |
| A08 / P2 | 批量移除一次，`objectWillChange` 实际发布两次；现有回归断言失败 | 额外 UI 更新。预算处理后统一提交一次集合变化，避免对相同值再次赋值 |

关键定位：[Claude 分类](../DynamicIsland/managers/Agents/Sources/ClaudeCodeAgentSource.swift#L43)、[Codex hook 清单](../DynamicIsland/managers/Agents/Sources/CodexAgentSource.swift#L14)、[审批回应](../DynamicIsland/managers/Agents/AgentConversationService.swift#L476)、[实时事件](../DynamicIsland/managers/Agents/AgentConversationService.swift#L608)、[hook reducer](../DynamicIsland/managers/Agents/AgentSession.swift#L180)、[断线处理](../DynamicIsland/managers/Agents/AgentSessionStore.swift#L214)、[有界插件队列](../DynamicIsland/managers/Agents/AgentPluginFile.swift#L88)。

A04 的旧 hook 回放直接提供了旧 `receivedAt`。真实 HTTP 桥接使用本机接收时间，并没有保留可靠的源事件顺序，因此不能只加一个时间比较就宣称乱序已修好；必须结合可用的 ID 和来源。A07 是队列容量边界回放，不是已证实用户当前遭遇了队列溢出。

### 各来源的边界

| 来源 | 本轮确认的特点 | 实施注意 |
| --- | --- | --- |
| Codex | shared service 有明确 active flags、回合和工具事件；hook-only 更新不完整 | 健康的 owner feed 决定运行状态，hook 补充宿主信息；不让两条路径争抢状态。外部终端的审批仍由终端处理 |
| Claude Code | 普通 Notification 过宽；工具失败和 API 失败未纳入 | 白名单分类、补齐结束路径；Stop 是本轮回答结束，不保证全部工作结束，可能被其他 Stop hook 续跑 |
| Antigravity | 使用 PreInvocation/PostToolUse/Stop；错误 Stop 有映射；没有当前安装的审批事件 | 不凭工具名或长时间静默猜“等你”；保留不参与全局权限决策的观察方式 |
| Pi | 用 `agent_settled` 而非每个模型回合结束；有 UI prompt 开始/结束 | 保留已选事件，携带工具及提示身份，避免并行工具覆盖 UI prompt；检查取消与续跑 |
| OpenCode | 有 permission/question 开始和回应，tool.completed 及 session.error/idle | 目前清除状态没有请求身份；取消后 idle 不应显示成功；队列关键事件不能被丢掉 |
| Grok Build | 已过滤 idle/task_complete 和子 Agent；未知通知仍升级，StopCancelled 为完成 | 先修保守分类与取消语义；本轮未取得完整官方 hook schema，不声称已核实所有 API 版本 |

官方对照：[Claude hooks](https://code.claude.com/docs/en/hooks#notification)列明 Notification 有不同类型，工具成功、工具失败与 StopFailure 也分开；Stop 能由其他 hook 继续，因此不足以证明整个任务已完成。[Codex hooks](https://developers.openai.com/codex/hooks)分别提供审批与工具返回，并说明其他审批 hook 可能先行决定；收到 PermissionRequest 不等于用户已经看到了弹窗。[OpenCode 插件](https://opencode.ai/docs/plugins#events)有独立的权限和会话事件。[Pi 类型](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/src/core/extensions/types.ts)说明 agent_settled 的边界及工具 ID。[Antigravity hooks](https://www.antigravity.google/docs/hooks)说明目前的调用、工具和停止事件。

这些来源确认当前公开语义，没有确认每个用户安装版本。后续新增 hook 必须有版本兼容策略；不能把新文档里的所有事件直接写进旧版配置。

## 实现选择

| 路线 | 收益 | 成本 / 结论 |
| --- | --- | --- |
| 现有事件通道 + 小的统一状态 reducer | 精确身份、去重、可回放；无新增高频扫描 | 需要补齐各适配器。推荐 |
| 高频扫描进程/转录文件来猜状态 | 接入未提供事件的工具较快 | 仍难确认审批，增加 I/O；仅作已有历史读取或明确标注的兼容信息 |
| 用模型分析内容和推断“是否等你” | 能解释自由文本 | 引入调用、延迟与误判；不纳入轻量方案 |

## 第一阶段：Agent 判断与提示

实现 A01–A08，保持输入保护与现有发送范围。数据不做无限历史，只保留有上限的当前活动、请求及必要去重键。

建议把“正在做什么”与“哪些请求等你”拆成两个小字段，显示层共用一份结果。当前来源能提供请求 ID 时按 ID 跟踪；不能提供时用保守的来源分类，不伪造请求 ID 或完成证据。健康的实时 owner feed 优先；转录文件主要用于内容，不从最后一句话推断完成。

| 实际情况 | 刘海呈现 | 提醒动作 |
| --- | --- | --- |
| 思考、处理工具 | 中性工作图标，可显示工具类型 | 不升级为“需要你” |
| 明确审批 / 问题未解决 | “等待审批” / “等待回答”，可同时表示其他工作还在运行 | 保留待处理标记；点击到对应会话或原终端 |
| 本轮明确成功结束 | “本轮完成”短暂显示一次 | 有新回合立即撤销；不表述为整个项目完成 |
| 本轮失败 | 错误状态与可读原因 | 可点击处理；单个工具失败不自动升级 |
| 用户取消 | 中性“已停止” | 不显示成功，不抢占音乐 |
| 连接丢失 / 信息不足 | “状态暂不可确认”，注明最后观察 | 不假装仍精确在线，不自动重发、不解锁可能回答审批的输入 |

完成状态去重之后，再增加轻微的呈现稳定窗口，避免几百毫秒的自动审批状态闪烁；具体延迟用实测选择。真实请求在稳定窗口内仍保留，不做按分钟轮询的通知系统。

只在明确知道用户正查看同一会话时减少动画和重复完成提示；不能仅因 Terminal.app 在前台就静音全部会话。未解决请求的标记不因用户看过一次就消失。

**验收：** 普通通知不会变待审批；另一工具完成/另一审批回答不会清除尚未解决的请求；旧回合不覆盖新回合；断线不产生假完成；取消不显示成功；同一完成只显示一次；审批中仍禁止将普通消息误输入审批界面。当前回放中的缺口应逐项转为断言通过。

## 第二阶段：功能选择清单与可选轻量预设

在现有 Settings 的核心区域增加“功能管理”入口，不加刘海 tab。复用当前 Defaults 和搜索/定位机制；逐个功能显示开关、用途、按需/后台工作、必要权限及详细设置入口。

提供“自定义”与“轻量建议”即可，不做多套自动切换的情景系统。应用预设前显示具体开关差异，保留之前设置以撤回；不在启动时重置用户选择。

基础音乐、Extra Space、Agents、Timer、Shelf 保留用户当前偏好。轻量预设建议先关闭实时波形、歌词、Stats 和不需要的相机/天气等可选项，不能盲目关闭每个看起来重的开关；先核实共享服务的依赖。

**Shelf 特别约束：** 当前关闭会清空托盘条目（原文件不删除），见 [关闭监听](../DynamicIsland/components/Shelf/ViewModels/ShelfStateViewModel.swift#L95)。预设必须排除这个开关，不能用“恢复设置”冒充恢复托盘内容。若以后改变生命周期，另行设计保留数据的明确语义。

资源信息在用户打开管理页时按需采样。先展示可核实的存储、缓存和服务状态；不声称能精确拆出各 SwiftUI 功能的内存占用，不为这页启动常驻性能扫描。

**验收：** 预览与实际变化一致；撤回不覆盖用户后续手动改动；Extra Space 内容、Shelf 条目不被预设清掉；关闭某功能后停止其非必要轮询，而共享的 Timer/Agent 事件继续工作；设置搜索能定位新入口。

## 第三阶段：让现有功能更顺手

1. 新增可配置的 Extra Space 直达快捷键。默认不占用新组合键；启用时打开对应 tab，关闭时指向设置入口；不会悄悄改变用户开关。
2. 保留统一默认高度、内部滚动、双击编辑、⌘S 保存退出和保存后上滑关闭。阅读模式直达不主动夺取输入焦点；显式编辑/粘贴动作才进入编辑。
3. 把现有 tab 拖动排序、会议加入、录屏隐藏入口放得更容易找到；不重复实现它们。点击 Agent 待处理提示应定位正确会话，源会话已结束则明确说明。
4. 框内持续保留 Copy all、Paste 等明确动作；导出纯文本属于小的后续便利项，排在状态准确性之后。

**验收：** 键盘/鼠标/双指手势结果一致；中文输入法未提交内容不丢失；⌘Z/⌘⇧Z、粘贴、保存失败与关闭恢复可用；快捷键不进入隐藏功能、不夺取阅读焦点、不覆盖现有组合键。

## 第四阶段：逐模块统一后台策略与长期验收

收敛现有启用、展开/收起、锁屏和低电量信号。可见 UI 才高频刷新，隐藏动画停止；按需服务暂停。重要 Timer 到期、Agent 事件、主动录音不能因“轻量模式”丢失。先接一个模块再推广，避免一次改全部 manager。

使用同机 Release、固定设置进行空闲/音乐/Agent/大文本/拖放各 10 分钟对照；比较 CPU time、footprint、唤醒、文件描述符和 UI 卡顿。随后做 24–72 小时含睡眠、多屏、连接恢复的运行验收。没有这两类测量，不给出“长期性能已保证”的结论。

## 本轮验证结果与局限

- 28 个定向状态场景：11 个符合拟定策略，17 个暴露缺口。多个场景属于同一个根因；这个比例不是全项目健康评分。
- 插件队列独立回放：32 项普通事件占满队列后，结束事件未转发；fake spawn，真实子进程为 0。
- 现有回归 15 个分组：14 个通过，1 个失败在批量移除一次却发布两次的断言。失败后单独运行剩余分组，已失败分组明确标记跳过，未称全通过。
- 原回归仍按同步保存/加载编写。本轮将该测试更新为等待异步加载和显式 flush，以便检查当前生产实现，没有放宽重复发布的断言。
- 两个 Swift 可执行回放均编译成功。保留既有 Sendable/捕获告警；受限编译环境还有宏插件警告，未将其称为产品故障。
- 没有运行真实 CLI、读取真实会话/凭据、更新真实 hook 配置、操作用户剪贴板、启动竞品、替换应用或提交本轮改动。真实版本兼容、UI 焦点及手势、前台静音、长期性能仍需实施后的现场验收。

证据：[汇总与源码哈希](audit/2026-10-06-agent-review/verification.json)、[状态回放结果](audit/2026-10-06-agent-review/state-observations.json)、[队列结果](audit/2026-10-06-agent-review/plugin-observations.json)、[剩余回归输出](audit/2026-10-06-agent-review/regression-remaining.log.md)。回放源码：[AgentStateAudit](../tests/AgentStateAudit.swift)、[插件队列回放](../tests/AgentPluginQueueAudit.mjs)，复用 [原有 fake 客户端与回归](../tests/AgentConversationRegression.swift)。

### 重跑状态诊断

在项目根目录执行，生成支持文件到临时目录，保留测试主程序但取消其 @main，供状态回放复用：

```sh
mkdir -p /tmp/atoll-agent-state-review
python3 - <<'PY'
from pathlib import Path
s = Path('tests/AgentConversationRegression.swift').read_text()
Path('/tmp/atoll-agent-state-review/RegressionSupport.swift').write_text(
    s.replace('@main\nstruct AgentConversationRegression', 'struct AgentConversationRegression'))
PY
xcrun swiftc -swift-version 5 -module-cache-path /tmp/atoll-agent-state-review/module-cache \
  DynamicIsland/managers/Agents/*.swift DynamicIsland/managers/Agents/Sources/*.swift \
  DynamicIsland/managers/Agents/Terminals/*.swift \
  DynamicIsland/utils/{AtollTemporaryFiles,PipeReadWaiter,PrivateContentFile}.swift \
  DynamicIsland/helpers/AppRuntimeEnvironment.swift \
  /tmp/atoll-agent-state-review/RegressionSupport.swift tests/AgentStateAudit.swift \
  -o /tmp/atoll-agent-state-review/state-audit
/tmp/atoll-agent-state-review/state-audit /tmp/atoll-agent-state-review/observations.json
node tests/AgentPluginQueueAudit.mjs
```

诊断程序正常退出只表示回放执行完成，必须查看 `met` 和 GAP；它不是“策略全部通过”的退出码。
