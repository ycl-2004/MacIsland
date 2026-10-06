# Atoll 刘海产品调研与优化建议 — 2026-10-06

**建议：把当前项目做成「随手暂存信息、查看工作状态、完成少量快捷操作」的轻量刘海工具。优先改善交互与功能管理，保留 Agent、Extra Space 和 Shelf 的特色。**

**用户已确认的产品边界（2026-10-06）：以轻量、好用、好管理为主；无限剪贴板历史、完整 AI 工作区、插件商店和新增复杂音频功能不进入开发范围。Terminal 仅作为后期候选，当前不实现。下列优化工作包仍是建议，不代表已经实现或启动。**

这轮覆盖 17 个刘海产品/项目（NotchNook 信息不完整）和 3 个相邻工具，结合本地源码提出取舍。Sapphire 是用户后续指定的重点，另做了固定提交的源码抽样。没有修改产品代码、安装竞品、运行其二进制、访问 Agent 凭据或调用 Claude CLI。

## 需求与证据范围

1. 判断当前项目的优化方向。
2. 搜索同类产品与开源项目。
3. 比较优势、限制和维护取舍。
4. 给出保留、按需启用、暂缓的功能建议。
5. 提出有优先级、能验收的下一轮工作。
6. 追加：定位 Sapphire，检查具体可参考的设计及其成本。

来源优先级：官方仓库/源码、官方文档、官方发布说明；搜索结果用于定位。表中的「限制」主要是针对我们的目标作出的判断，不能当作实测故障。没有同机、同功能、同版本的竞品性能测试，不能给出可信的内存、功耗或流畅度排名。各厂商的「0% CPU」「轻量」属于自述。

本地依据：[修复报告](project-audit-fixes-2026-10-06.md)、[架构](architecture.md)、[Extra Space](extra-space.md)，以及 TabSelectionView、Constants、SettingsView、Calendar、Extra Space 和 Agent 的相关源码。

## 当前项目：已有能力与真正缺口

| 已确认的本地能力 | 下一轮值得优化的地方 |
| --- | --- |
| 主要 tab 为 Home、Shelf、Timer、Stats、Agents、Extra Space；已有启用开关和拖动排序 | 给出明确的默认组合，新增功能尽量使用现有页面或短暂提示；避免 tab 越来越多 |
| 设置已有搜索、分组和高亮定位 | 增加一个简洁的功能总览：启用状态、权限、是否正在工作；高级设置收进现有分组 |
| Stats、真实波形、歌词默认关闭；Stats 有可见性生命周期，后台保存和缓存已有上限 | 将分散的节流规则收敛为共同的运行状态，便于检查收起/低电量/休眠后的实际行为 |
| Extra Space 是连续文本；双击编辑、⌘S 结束编辑、保存后上滑收起；5 MiB 限制和上一版恢复 | 增加直达快捷键、明确的复制/纯文本粘贴入口、可选导出；保留已确认的读写与收起交互 |
| Agent 有 hook 事件、等待提示、会话卡片和短暂完成状态；不同来源的可回复能力有边界 | 改善完成/失败/等待提示的去重、前台静音与点击回到原会话；不要误把所有来源都显示成可批准 |
| Calendar 已识别会议链接，已有 Join Meeting 入口 | 优化「下一场会议」的可见性即可，不必新写会议系统 |
| Shelf 已有拖放、缩略图、文件引用及存储预算；tab 有内容提示 | 明确「从托盘移除」与「删除原文件」的区别；按需增加过期/固定规则，不能自动清理用户原文件 |
| 已有隐藏于截图/录屏的开关，默认 false；有 hover 延迟和全局开合快捷键 | 给演示场景一个容易找到的预设，把隐藏与暂停弹出分开解释 |
| SettingsView 当前约 6,971 行，设置索引、页面与大量细节聚在一处 | 后续改到哪个模块就拆哪个模块；建立共享功能描述，减少重复开关/搜索/权限文案，避免整仓重构 |

这些是源码默认值和实现情况，不代表用户当前保存的设置。上一轮审计的约 111 MiB RSS 和 45 秒 CPU 快照来自修复前、非受控场景，不能作为最新版 idle 基准。

## 同类产品与项目

「参考价值」表示适合我们的设计方向，不是购买排名。

| 产品 / 项目 | 可确认的优势 | 对我们目标的限制或取舍 | 参考价值 |
| --- | --- | --- | --- |
| [boring.notch](https://github.com/TheBoredTeam/boring.notch) | 可读源码，与我们有共同来源；媒体、Shelf 和日历基础齐全 | 功能继续扩张；不能把 RC 的全部功能直接合并到个人稳定版 | 高：优先挑可靠性补丁 |
| [原版 Atoll](https://github.com/Ebullioscopic/Atoll) | 当前架构的直接上游，系统 HUD、Stats、计时和锁屏经验最接近 | 大量工具不是我们的必需项；整体同步会重新增加范围 | 高：选择性回移 |
| [Sapphire](https://github.com/cshariq/Sapphire) | 活动分类、后台节流、布局策略有具体实现；还有护眼提醒等差异功能 | 范围很大；Notes 仍为多条富文本；公开构建不等于全部官网能力 | 高：借设计，控制功能范围 |
| [Alcove](https://tryalcove.com/) | 官方突出过渡、手势、通知、活动和锁屏；适合研究小面积状态的呈现 | 非开源；公开发布仓库于 2026-06-01 归档，不能据此断言产品停止维护 | 高：视觉与交互参考 |
| [MediaMate](https://wouter01.github.io/MediaMate/) | 专注音量、亮度、键盘背光和 Now Playing，范围清楚 | 不覆盖我们的连续文本和 Agent 工作流；系统 HUD 集成仍需要兼容验收 | 高：克制的产品范围 |
| [NotchDrop](https://github.com/Lakr233/NotchDrop) | 专门做临时文件与 AirDrop；保留期限可配置；MIT | 功能较窄；缺少完整的工作状态与文本空间 | 高：Shelf 生命周期 |
| [Droppy](https://getdroppy.app/docs/shelf) | 固定条目、过期清理、拖出后移除、保护原文件、逐显示器行为有文档 | 已扩张成大量扩展；当前官方为付费产品，旧免费仓库/分支不能代表现售版本 | 高：文件交互与按需启用 |
| [DynamicLake](https://www.dynamiclake.com/blog/dynamiclake-market-and-plugins) | 区分持续活动与短暂 Sneak Peek；现有插件可承载完成、Agent、日历状态 | 平台/插件市场与通信、转换工具会带来较大维护范围 | 高：短暂信息的出现时机 |
| [FloatPill（原 dynamicnotch.app）](https://floatpill.com/) | 官方强调 Agent 完成/需要用户时提示、用户已在查看时保持安静，以及相机按需开启 | 还有语音、视频与用量读取；不能把厂商 CPU 数字当竞品实测结果 | 高：少打断的提醒 |
| [Dynamic Notch（dynamicnotch.tech）](https://www.dynamicnotch.tech/) | 临时文字、当前任务、会议加入、文件引用式下载入口 | 音乐/日历/取色多数我们已有；不是上面的 FloatPill，也不是下面的 GitHub 项目 | 中：一个「当前任务」提示 |
| [DynamicNotch（Hitjack007）](https://github.com/Hitjack007/DynamicNotch) | boring.notch 分支，含热量/风扇、CPU、媒体和自动化 | 风扇曲线、常显监控、helper/daemon 超出轻量刘海的核心范围 | 低：不引入硬件控制 |
| [Notchy](https://notchy.dev/) | 官方列有命令面板、快捷切 tab、片段和按需截图/OCR | 广泛的工具集合；官网对其他产品的比较不作为事实来源 | 中：只借轻量动作入口 |
| [Notchi（sk-ruban）](https://github.com/sk-ruban/notchi) | 基于 Agent 事件的状态、并行会话、前台静音提示 | 情绪 API、角色动画、成本统计不是我们核心；使用范围较专门 | 中高：状态，不加情绪分析 |
| [Notchi（cyrus-cai）](https://github.com/cyrus-cai/notchi) | 输入可转成 Note、Reminder、Agent 任务，MIT；支持 Apple Notes/Markdown | AI 意图识别、提供商和 CLI 编排增加配置与成本；与上一个 Notchi 不同 | 中：明确按钮优于自动猜意图 |
| [ClaudeNotch（rawsun007）](https://github.com/rawsun007/claude-notch) | 把命令/diff、Allow/Deny 放在提示中；解决频繁回终端的工作流 | 这是权限入口，复杂度高；该项目对 Claude 和 Codex 的行为也不同 | 中：展示信息，不先扩张批准能力 |
| [NotchPrompter](https://github.com/jpomykala/NotchPrompter) | 摄像头附近阅读、字号/速度/位置、多显示器；项目宣称录屏隐藏 | 独立提词工具，不是普通便笺；语音触发不是轻量 MVP | 中：有录视频需求再做阅读模式 |
| [NotchNook（lo.cafe）](https://lo.cafe/notchnook) | 历史上以 Nook/Tray 的工作区与文件区组合为参考，NotchDrop 作者有明确致谢 | 本轮官网读取失败，Setapp 英文链接转到总目录；当前功能/价格/维护状态未独立确认 | 历史参考，保留信息缺口 |

补充来源：[boring.notch 2.8 RC 发布说明](https://github.com/TheBoredTeam/boring.notch/releases/tag/v2.8-rc.0)明确列出紧凑播放器、会议加入、Shelf 行为和生命周期修正；适合挑选补丁，不能将 RC 当稳定性证明。[Alcove 仓库](https://github.com/henrikruscon/alcove-releases)明确说明没有产品源码。[Droppy 当前许可页](https://getdroppy.app/docs/license)列出付费与试用；不能继续笼统称其现售版本免费。[NotchNook 开发者的致谢](https://github.com/Lakr233/NotchDrop/issues/14)确认历史项目关联，但不能验证今天的完整功能。

### 相邻工具也值得看

| 工具 | 值得借的部分 | 取舍 |
| --- | --- | --- |
| [Dropover](https://dropoverapp.com/) | 临时文件流程、批量操作、Quick Look、系统分享/Services、动作入口；也有 notch drop 支持 | 学常用交互即可，云上传、脚本平台与复杂处理链不必重做 |
| [Unclutter](https://unclutterapp.com/) | 顶边下滑打开，文件/文字/剪贴板分区，可关掉不用的面板 | 比更复杂的刘海套件更接近临时工作空间；保留我们的单文档语义，别照搬多便笺系统 |
| [TopNotch](https://topnotch.app/) | 明确只解决外观和壁纸、多屏问题 | 功能很窄，不能替代现项目；可参考默认安静的定位 |

## Sapphire 专项：最值得借什么

抽样提交：`dac4dd52e12cc419c28ebea0664ed1412a44f1e8`（本轮 main；对应 v3.4 预发布提交）。取回 25 个公开文件、约 399 KB，对下列关键模块定向检查。完整文件清单见 [研究证据](research/notch-landscape-2026-10-06.json)。没有构建或运行 Sapphire。

### 1. 统一后台工作状态：最高优先级

[NotchRuntimeState](https://github.com/cshariq/Sapphire/blob/dac4dd52e12cc419c28ebea0664ed1412a44f1e8/Sapphire/Notch/NotchRuntimeState.swift#L29)聚合多个窗口来源：有已注册来源、用户不靠近、刘海也未展开时，发布减少后台工作的信号。

[DevActivityMonitor](https://github.com/cshariq/Sapphire/blob/dac4dd52e12cc419c28ebea0664ed1412a44f1e8/Sapphire/Services/DevActivity/DevActivityMonitor.swift#L121)实际消费这个信号，把普通开发任务扫描从 2.5 秒放慢到 5 秒；启用自动防休眠任务检测时例外。Clipboard 也订阅该状态。**这证明有统一的节流机制，不证明整应用已经低功耗。**

我们已有若干关闭即停止的规则。下一步可以共用「显示/收起、锁屏、低电量、功能是否启用」状态：降低不影响操作的图表刷新，停掉不可见动画；保留 Timer 到期、Agent 等待和主动录音等必要事件。按每个模块逐步接入，避免一次改全部 manager。

### 2. 活动优先级：改善管理成本

[LiveActivityRegistry](https://github.com/cshariq/Sapphire/blob/dac4dd52e12cc419c28ebea0664ed1412a44f1e8/Sapphire/LiveActivities/LiveActivityRegistry.swift#L13)区分紧急、用户排序、环境信息；提供统一的候选检查和短暂活动集合。

我们已经有活动优先级，不需要重新发明。可逐步把分散的条件收敛到小的活动描述表，并明确哪些短暂提示可以让位、哪些需要用户处理。建议测试 Agent 等待、Timer 到期、音乐、充电提示同时到达时的呈现；减少无意义的反复展开。

### 3. 布局有预算：保留固定默认高度

[WidgetLayoutPolicy](https://github.com/cshariq/Sapphire/blob/dac4dd52e12cc419c28ebea0664ed1412a44f1e8/Sapphire/Notch/WidgetLayoutPolicy.swift#L38)按显示器宽度、组件估算宽度和顺序筛选可容纳项目。

借「空间有限，先预算」的原则即可。我们继续保持同层 tab 与统一默认高度，长内容内部滚动；可选的更大尺寸放设置。超出的动作进现有菜单，不把整个刘海自动拉大，也不把 tab 换成横向大仪表盘。

### 4. 护眼提醒：成本较小的可选功能

[EyeBreakManager](https://github.com/cshariq/Sapphire/blob/dac4dd52e12cc419c28ebea0664ed1412a44f1e8/Sapphire/Services/Miscellaneous/EyeBreakManager.swift#L123)提供工作/休息周期和暂停恢复；其工作及休息阶段使用 1 秒 timer。

这是值得保留的候选，但我们只需要 Timer 中一个可选预设，到时出现短暂提示。无需新的 tab、每日评分、复杂历史，也不必全天每秒刷新 UI。默认关闭、能延后、会在锁屏/休眠时正确暂停。

### 不建议照搬的部分

- **Notes 实现**：[NotesManager](https://github.com/cshariq/Sapphire/blob/dac4dd52e12cc419c28ebea0664ed1412a44f1e8/Sapphire/Services/Notes/NotesManager.swift#L65)是多条 QuickNote，带可选 RTF；更改时在 MainActor 编码整个数组并交给 UserDefaults。适合小便笺，和我们的连续纯文本、后台保存及容量控制不同；这里没有同机性能实测，不能断言它一定卡。
- **开发工具检测作为主要来源**：[DevActivityMonitor](https://github.com/cshariq/Sapphire/blob/dac4dd52e12cc419c28ebea0664ed1412a44f1e8/Sapphire/Services/DevActivity/DevActivityMonitor.swift#L61)周期扫描，[DevProcessScanner](https://github.com/cshariq/Sapphire/blob/dac4dd52e12cc419c28ebea0664ed1412a44f1e8/Sapphire/Services/DevActivity/DevProcessScanner.swift#L63)读取当前用户进程，[DevAgentSessionActivity](https://github.com/cshariq/Sapphire/blob/dac4dd52e12cc419c28ebea0664ed1412a44f1e8/Sapphire/Services/DevActivity/DevAgentSessionActivity.swift#L27)用会话文件最近修改时间推断活跃。我们继续以已有 hook 事件为主；泛用构建/测试检测有明确需求后再评估，且不把推断标成准确的「等待批准」。
- **完整 Blip**：[公开占位视图](https://github.com/cshariq/Sapphire/blob/dac4dd52e12cc419c28ebea0664ed1412a44f1e8/Sapphire/Stubs/BlipHubView.swift#L7)在非 FULL_BUILD 显示不可用；本轮公开 tree 中相关 Intelligence 也有 stubs。官网能力不能直接当成公开可复用实现。
- **Face ID、亮度超频、复杂 EQ/虚拟音频、窗口吸附、体育/金融、Android 分享、无限剪贴板**：[官网](https://sapphire-app.tech/)展示这些方向；它们离我们的主要目标较远，增加系统集成、数据来源或后台工作。不把它们列为下一轮必做。
- **直接复制代码**：当前 [Sapphire LICENSE](https://github.com/cshariq/Sapphire/blob/dac4dd52e12cc419c28ebea0664ed1412a44f1e8/LICENSE)为 AGPL-3.0；本项目是 GPL-3.0。后续引用代码需核对许可与归属，本轮仅借设计原则。

[发布页](https://github.com/cshariq/Sapphire/releases)把 3.4 标为预发布，3.0 的说明也明确承认早期版本可能有问题。用户报告如 [重复窗口 #104](https://github.com/cshariq/Sapphire/issues/104)可转成我们多屏/休眠的测试场景，不能据此断言最新版仍有同一缺陷。

## 我们应该继续使用什么

| 选择 | 功能 | 原因 |
| --- | --- | --- |
| 核心保留 | Extra Space、Agent 状态、Shelf | 临时内容与工作状态有即时价值，构成我们自己的用途 |
| 保留简洁入口 | 基本音乐控制、Timer、取色器、下一场会议 | 可用现有界面完成，不需要再开一套应用 |
| 按需启用 | Stats、歌词、实时波形、锁屏天气、Mirror、每应用音量 | 是否值得常驻取决于实际频率；保持关闭时不做相应后台工作 |
| 不纳入开发范围 | 完整 AI 工作区、无限剪贴板历史、插件商店、新增复杂音频功能 | 用户已明确排除；保持轻量，Extra Space 继续使用连续文本 |
| 后期候选 | Terminal | 用户唯一考虑增加的这类功能，但当前不实现 |
| 暂缓新增 | 视频播放器、语音助手 | 范围与维护成本大，当前没有明确需求 |
| 有需求再做 | 简单护眼预设、提词阅读、有限常用动作 | 范围可小，但要先确认日常使用价值 |

建议的个人默认组合是 Home、Extra Space、Agents；Shelf 在拖放或有条目时容易进入；Timer 运行时突出，Stats 需要时才看。它是下一轮设计建议，不是本轮变更，也不意味着删除现有 tab 或丢弃保存的内容。

## 下一轮：三个优先工作包

### A. 功能总览与可选轻量模式

一页列出功能的启用、实际运行、权限与数据位置；提供可选轻量预设，能预览会改哪些开关并恢复。资源数值按用户打开页面时采样，不为「管理性能」再开一套高频常驻监控。

逐模块共用运行状态。对开关做实际验收：关闭不再轮询/启动相应子进程；重要事件仍可到达。没有必要构建第三方插件市场。

### B. 交互与直接入口

统一默认面板高度、hover/点击/键盘的入口和焦点返回。Extra Space 维持双击编辑、⌘S 保存退出、保存后上滑关闭；短暂提示不能默默进入编辑或夺取焦点。新增一个可配置的 Extra Space 直达快捷键；需要写入剪贴板内容时使用明确动作和现有容量校验。

设置搜索、tab 排序、录屏隐藏、会议加入已存在，工作是优化入口和组合，而不是重复实现。文件移除与原件删除保持不同语义。

### C. 工作完成提醒与可管理的内容

Agent 完成/失败/需要用户时，先去重与前台降噪，再显示短暂提示或保留待处理标记；点击回到对应会话。沿用已有事件与批准范围。给 Extra Space 一个显式导出入口，给 Shelf 可选固定/过期规则；先显示存储占用与候选条目，再执行用户选定的清理。

若再做一个新功能，优先考虑借用现有 Timer 的简单护眼预设。完整提词模式放在有频繁录视频需求之后。

## 性能与长期维护的验收

这些是拟定的下一轮检查，不是已通过的结果：

- 同一硬件、Release、同一设置：空闲、音乐播放、Agent 工作、大文本、批量拖放各 10 分钟；统计主进程和 helper 的 CPU time、内存 footprint、唤醒、UI 卡顿。
- 24–72 小时记录启用项、RSS/footprint、文件描述符、会话/缓存数量，包含多屏插拔、锁屏、睡眠唤醒；区分缓存热身与持续增长。
- 验收焦点和内容：输入法未完成文本、粘贴/撤销、保存失败、快捷键、保存后收起、退出恢复；关闭功能后仍保留用户数据。
- 选择性回移上游：优先 bug/lifecycle 修正，稳定版与 RC 分开；保留当前窗口布局与内容回归。原生 AppKit + SwiftUI 继续使用，不需要换技术栈。
- 设置按模块逐步拆分；依赖、权限、存储与后台服务的说明同一处维护。性能预算来自受控实测，不来自安装包大小或源码文件数量。

## 信息缺口

NotchNook 官网与当前销售/维护未完整验证；MacNotch 等额外搜索命中仅作候选，没有足够读取证据就不加入正式比较。没有运行竞品、完整审计其所有源码、验证厂商安全/性能宣称，也没有声称覆盖市场上全部刘海软件。本轮结果适合筛选设计方向；具体新增功能仍应小范围实现后验收。
