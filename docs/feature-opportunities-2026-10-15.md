# Atoll 功能机会评估 — 2026-10-15

建议优先考虑快捷操作面板、截图取字、Shelf 固定/到期整理和一键演示模式。首个实现批次只选两项：快捷操作面板 + 截图取字。它们能复用现有能力，按用户操作运行，也能直接缩短日常操作路径。

本轮是功能评估，候选项尚未实现。判断基于当前工作区，包含未提交的修改；没有以 Git HEAD 或旧调研替代当前源码。没有修改应用代码、运行应用、访问真实 Agent 会话或调用 Agent CLI。

## 评估要求与边界

1. 盘点现有功能和已经落地的旧建议。
2. 筛选仍值得增加的能力，说明最小范围、代价与验收方式。
3. 给出优先级和推荐组合，保留既定产品范围。

继续遵守 [产品范围](architecture.md#product-scope)：轻量刘海工具，服务临时内容、工作状态和少量快捷操作。无限剪贴板历史、完整 AI 工作区、插件市场、新增复杂音频功能不进入范围；Terminal 仍为后期候选。本次未重新开展完整竞品调研。

成本的“小/中”是基于现有模块复用程度、状态迁移和系统集成范围的相对判断，不是排期承诺。日常使用频率、实际收益和新功能资源开销尚未实测。

## 当前已经具备的能力

| 领域 | 当前实现 | 评估结论 |
| --- | --- | --- |
| 主面板 | Home、Shelf、Timer、Stats、Agents、Extra Space；按启用状态显示和拖动排序 | 优先增加现有页面中的动作，控制新增 tab |
| 功能管理 | 功能总览、权限/部分运行状态、轻量建议预览和撤回、按需资源计数 | 无需再提出“从零增加功能管理” |
| Extra Space | 连续纯文本、双击编辑、保存退出、直达快捷键、纯文本粘贴、复制、查找、导出、前一版本恢复 | 新增机会在外部内容进入路径，保持单文档语义 |
| Agent | 多来源状态、待处理标记、完成提示、会话回复、回到终端、圈选屏幕提问 | 提示去重和前台降噪已经存在；可考虑筛选与短期结果记录 |
| Shelf | 文件/文本/链接、拖入拖出、多选、预览/分享等动作、拖出后移除选项；隐藏保留内容 | 固定与按年龄整理仍有空间；“拖出自动移除”不是新功能 |
| Timer | 自定义预设、25 分钟 Focus、5 分钟 Break、45 分钟 Deep Work；暂停/恢复/重启与恢复持久化 | 新增点是阶段衔接或周期，不能把普通番茄钟预设当作缺失 |
| 日历 | 日程/提醒事项、会议链接加入、提前提醒和倒计时 | 不必重做“下一场会议提醒”；可缩短提醒到加入会议的路径 |
| 下载 | 目录事件观察、下载速度和完成提示 | 可把已确认的完成文件接到实际操作 |
| 媒体/系统 | 多播放器、歌词、波形、系统 HUD、锁屏组件、隐私/录屏状态、连接提示等 | 现有范围已广，不优先继续扩展重型系统能力 |
| 稳定性 | 已有保存协调、后台节流、有界队列、服务重试、诊断导出和自动验证工具 | 不能把旧审计中的已修复问题重复列成当前功能缺口；长期真机验收仍是单独事项 |

现有实现依据：[功能总览](../DynamicIsland/components/Settings/FeatureManagementSettings.swift)、[轻量预设](../DynamicIsland/managers/FeaturePresetController.swift)、[tab](../DynamicIsland/components/Tabs/TabSelectionView.swift)、[Extra Space](../DynamicIsland/components/Notch/NotchExtraSpaceView.swift)、[Agent 面板](../DynamicIsland/components/Agents/NotchAgentsView.swift)、[Timer 预设](../DynamicIsland/models/TimerPreset.swift)、[Shelf 生命周期](shelf-lifecycle.md)、[已实施稳定性修复](stability-fixes-2026-10-10.md)、[后台背压修复](background-backpressure-fixes-2026-10-10.md)。

## 候选总表

| 顺序 | 功能 | 类型 | 用户收益 | 相对成本 | 建议 |
| --- | --- | --- | --- | --- | --- |
| 1 | 快捷操作面板与键盘导航 | 新入口，复用动作 | 少找设置、少切 tab，常用动作可直接触达 | 中 | 首批 |
| 2 | 本地截图取字 | 新能力 | 圈选图片、报错或视频画面，复制文字或追加到 Extra Space | 中 | 首批 |
| 3 | Shelf 固定与到期整理 | 现有能力扩展 | 保留常用材料，临时内容不长期堆积 | 中 | 下一批 |
| 4 | 一键演示/安静模式 | 现有能力组合 | 分享屏幕或专注时减少弹出、隐藏私密预览，结束后恢复 | 中 | 下一批；高频演示者可提前 |
| 5 | 选中文字快速追加到 Extra Space | 新入口 | 在其他应用里把一段文字随手存进同一文档 | 小至中 | 紧随首批，复用内容写入动作 |
| 6 | 最近活动小列表 | 新能力 | 错过几秒提示后仍能回看结果 | 中 | 有漏看完成提示的问题再做 |
| 7 | Agent 按项目/状态筛选与别名 | 现有能力扩展 | 多会话时更快找到需要处理的项目 | 小至中 | 多会话高频使用时做 |
| 8 | 工作/休息阶段衔接 | 现有能力扩展 | Focus 到期后可直接进入 Break，并可选择简单周期 | 中 | 用计时器工作的人优先 |
| 9 | 下载完成后的文件动作 | 现有能力扩展 | 完成后直接在 Finder 显示、打开或加入 Shelf | 中 | 下载多时做 |
| 10 | 设置导出与导入 | 新能力 | 重装、换机或调整失败后恢复个人配置 | 小至中 | 维护便利项 |
| 11 | 原生 Shortcuts 动作 | 新系统入口 | 让外部快捷指令调用 Atoll 的少量稳定动作 | 中 | 等内部动作稳定后做 |
| 12 | 日程提醒上直接加入会议 | 现有能力扩展 | 减少从提醒回到 Home 再找 Join 的步骤 | 小至中 | 会议多时做 |

## 优先四项的最小范围

### 1. 快捷操作面板与键盘导航

当前已有全局开合、圈选提问、取色、Extra Space 直达等快捷键，但没有集中搜索动作的面板。建议在刘海内提供一个简洁入口：输入“计时”“取字”“便笺”“演示”等关键词，方向键选择，回车执行；增加打开面板后的键盘切页与 Esc 返回。

首版只放少量既有动作和本次新增动作，例如打开 Extra Space、启动现有 Timer 预设、打开 Shelf、查看待处理 Agent、取色和进入演示模式。沿用设置搜索的相关词，不增加任意 shell 命令执行器，也不自动猜测用户意图。功能关闭时打开对应设置，保持当前直达入口的语义。

验收：只用键盘可完成常用动作；关闭后焦点回到原应用；中文输入法组合输入不被快捷键截断；面板收起后不保留搜索任务或新增轮询。

依据：[快捷键定义](../DynamicIsland/Shortcuts/ShortcutConstants.swift)、[tab 导航](../DynamicIsland/components/Tabs/TabSelectionView.swift)、[设置搜索](../DynamicIsland/components/Settings/SettingsView.swift)。

### 2. 本地截图取字

当前圈选截图进入 Agent 问答，未发现 Vision OCR 实现。建议复用圈选交互，新增独立“取字”动作：选区后展示可编辑的识别文本，由用户选择复制或追加到 Extra Space。普通文字提取无需启动 Agent。

Apple 官方说明 Vision 的文字识别处理在设备端执行，可从图片中提取多语言文本。该能力适合作为实现基础；中文、混合代码、低分辨率与多栏阅读顺序仍需用真实样本验收。[Apple：Recognizing Text in Images](https://developer.apple.com/documentation/vision/recognizing-text-in-images?changes=_1)

实现时让截图获取与 Agent 发送解耦，避免“取字”误发模型请求。首版不承诺表格还原、文档版式重建或持续屏幕识别。

验收：取消选区不写入内容；无文字时给出明确结果；追加可撤销且遵守现有容量限制；识别期间可取消；截图临时文件按当前生命周期释放。

依据：[圈选入口](../DynamicIsland/managers/Agents/Assistant/ScreenQuestionManager.swift)、[文本存储](../DynamicIsland/managers/ExtraSpaceStore.swift)、[Extra Space 编辑器](../DynamicIsland/components/ExtraSpace/ExtraSpaceTextView.swift)。

### 3. Shelf 固定与到期整理

目前模型没有固定标记或加入时间。建议先提供固定、按加入时间查看，以及显式“整理过期条目”；之后再考虑可选自动规则。已有的拖出后移除继续独立工作。

最小设计：增加可迁移的加入时间与固定状态；旧条目不凭空推算年龄，也不在首次升级时清理。固定条目跳过到期整理，但仍受现有条目/容量预算约束。默认关闭自动整理，手动整理前可预览。

验收：只移除托盘引用和按现有规则可回收的 Atoll 自有临时数据；保留用户原文件和活跃文件交接；关闭 Shelf、重启和旧数据迁移都保留固定状态。到期判断在使用时或最近截止点处理，避免每秒扫描整个托盘。

依据：[ShelfItem](../DynamicIsland/components/Shelf/Models/ShelfItem.swift)、[状态管理](../DynamicIsland/components/Shelf/ViewModels/ShelfStateViewModel.swift)、[文件所有权](shelf-lifecycle.md)。

### 4. 一键演示/安静模式

已有录屏隐藏开关、全屏媒体检测和系统专注状态显示，但没有统一的临时演示预设。建议通过菜单或快捷动作手动进入：收起私密内容、暂停非必要弹出、保留待处理事实；退出后恢复原来的表现设置。

首版可限定为“只显示中性状态”与“暂时隐藏 Atoll 窗口”两种选择。不要自动结束 Timer、Agent 会话或丢弃待处理请求；对到期提示是否允许出现给出明确选择。用临时覆盖层管理，避免退出模式时覆盖用户后来手动改过的设置。

现有录屏隐藏通过 `NSWindow.sharingType` 设置，源码中的开关不能代替真实录屏验收。是否被各录屏/会议工具采集必须分别确认；产品文案应区分减少打断、隐藏预览和捕获排除。

验收：进入/退出可逆；没有私密预览闪现；用户能通过菜单/快捷键退出隐藏状态；中途改设置、锁屏/解锁、接外屏和计时到期均有确定行为。

依据：[窗口捕获设置](../DynamicIsland/helpers/ScreenCaptureVisibilityManager.swift)、[功能预设恢复机制](../DynamicIsland/managers/FeaturePresetController.swift)、[共享运行策略](architecture.md#shared-runtime-policy)。

## 其余候选的范围与取舍

| 候选 | 最小范围与现有缺口 | 主要取舍 / 验收 |
| --- | --- | --- |
| 选中文字快速追加 | 通过明确的服务菜单动作或用户主动复制后追加；保留单一 Extra Space 文档。当前 Paste 需要先进入编辑器 | 追加可撤销；正在输入中文时不覆盖组合文本；容量或保存失败时保留原文。避免为此常驻监听剪贴板 |
| 最近活动小列表 | 先保留最近 20 条 Agent 明确完成/失败结果，最长 24 小时；放现有 Agents 弹层。需要时再接 Timer/下载 | 现有完成高亮为 6 秒，当前会话状态不等于历史。按回合去重，仅记短标题、来源和时间；旧记录不带可执行审批按钮；不把历史结果当作当前状态 |
| Agent 筛选与别名 | 使用现有 `cwd`/`projectName`，提供项目、待处理、来源筛选和本地显示别名 | 不增加新的进程扫描或 transcript 抓取；“未提供项目”单列；同名目录按实际路径区分。首版不固定保活会话，保持现有淘汰预算 |
| 工作/休息阶段衔接 | 已有 Focus/Break 预设；新增“休息 5 分钟”下一步按钮，再考虑可选的 25/5 周期 | 默认不自动开下一轮；定义暂停、跳过、锁屏/睡眠和恢复后的阶段，避免过期后补发多次提醒 |
| 下载文件动作 | 当前完成检测得到文件名，但没有提供给 HUD 操作的完成文件集合。保留有界的已确认文件引用，再提供显式按钮 | 浏览器命名只是启发式来源；多文件、取消、覆盖下载、移动和同名文件须验证。失效引用提示用户，不按猜测路径自动打开 |
| 设置导出/导入 | 仅导出允许列表中的功能开关、布局与预设；导入先展示差异，支持撤回 | 不导出 token、Agent 配置、会话、权限授权或内容数据；不原样倾倒整个 UserDefaults。未知键忽略，格式带版本 |
| 原生 Shortcuts 动作 | 先暴露“追加文本”“启动 Timer”“打开指定页面”三项内部稳定动作 | App Intents 可向 Shortcuts 提供动作，Mac 可组合调用；按最低支持系统核对具体 API，不承诺所有系统入口一致。[Apple AppIntent](https://developer.apple.com/documentation/AppIntents/AppIntent)、[Mac Shortcuts](https://support.apple.com/guide/shortcuts-mac/intro-to-shortcuts-apdf22b0444c/mac) |
| 提醒上直接加入会议 | 已有日程提醒与 Home Join；新增提醒展开区域的 Join 动作，使用已有会议链接 | 有链接才显示；冲突会议可选；沿用现有链接处理与事件去重。紧凑状态仍保持固定尺寸，不为一个按钮重做日历 |

补充依据：[会话模型](../DynamicIsland/managers/Agents/AgentSession.swift)、[会话高亮及淘汰](../DynamicIsland/managers/Agents/AgentSessionStore.swift)、[下载检测](../DynamicIsland/managers/DownloadManager.swift)、[下载 HUD](../DynamicIsland/components/Downloads/DownloadLiveActivity.swift)、[日程提醒](../DynamicIsland/managers/ReminderLiveActivityManager.swift)、[提醒视图](../DynamicIsland/components/Calendar/ReminderLiveActivity.swift)、[Home 会议加入](../DynamicIsland/components/Calendar/DynamicIslandCalendar.swift)。

## 暂缓方向

- 完整终端和新的 Agent 工作区：维护输入、输出、权限、会话恢复的成本高；继续留作后期独立评估。
- 提词阅读模式：能复用连续文本，但需要自动滚动、可读性和摄像场景验收；有稳定录制需求后再做。
- 泛用构建/测试任务通知：以后可评估用户主动触发的完成事件；当前不增加后台进程扫描，也不把所有任务编排进 Atoll。
- 云同步、多文档笔记、语音助手、复杂音频和新增常显监控：当前没有足够需求依据，且会增加后台工作与维护范围。

## 推荐组合与成功信号

通用下一版选“快捷操作面板 + 截图取字”，并把复制/追加文本做成可复用的明确动作。两项都按用户触发运行；新增后台成本应在操作结束后回落。

如果最近主要在演示或录屏，演示模式可以替换快捷操作面板进入首批。如果主要靠 Shelf 中转文件，则先做固定和手动到期整理。以上是使用场景取舍，不是已收集到的使用数据。

成功信号：常用动作不再需要反复找设置；截图文字不必走模型问答；操作结束不新增常驻轮询；中文输入、原应用焦点、内容保存和现有活动提示不回归。实际操作步数、识别质量和资源数据应在实现后实测，不预报收益百分比。

## 本轮检查与限制

- 已查阅 README、架构、前轮调研/实施记录及上述相关源码；检查当前 Git 状态，保留现有修改。
- 通过相关字段、调用和全仓关键词检索检查候选是否重复；未发现 OCR、App Intents、集中动作面板、Shelf 固定/到期元数据或统一演示模式的实现。检索缺失不等于形式化证明，结论限定于本次检查的工作区。
- 已用 Apple 官方资料核对设备端 OCR 与 Shortcuts 动作的可行方向。部分开发文档正文被 JavaScript/抓取内容类型限制阻挡，使用可读取的官方搜索正文及 Mac 用户指南交叉核对；未将抓取失败当作完整 API 兼容性验证。
- 本轮只新增本评估文档；完成本地链接、条目数量及 diff 格式检查。没有重新构建或运行测试，因为没有修改应用代码；当前安装版、真实录屏效果、候选运行体验和实际排期均未验证。
