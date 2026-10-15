# Atoll 稳定性修复与长期调试

日期：2026-10-10。对应[修复前审计](stability-review-2026-10-10.md)中的 R01–R12，以及随后用户的 `fix all`。

代码加固、故障回归和本地构建是本轮交付范围；用户随后明确要求替换应用，已将签名后的修复版安装到 `/Applications/Atoll.app` 并启动，原应用已备份。**长期稳定版验收仍须在这份 Release 产物上完成真机组合测试和 24–72 小时运行**。本轮保留原有 Stats 改动，自动测试使用隔离宿主与合成 Agent fixture；没有直接调用真实 Agent CLI 或检查其凭据/会话，没有提交或推送。

## 修复与证据对应

| 风险 | 已实施 | 验证与剩余边界 |
| --- | --- | --- |
| R01 退出保存 | `AppTerminationCoordinator` 统一 Quit/Restart，AppKit 延后退出；初始内容加载完成后才记录快照，异步保存 Extra Space、Shelf、Agent 缓存/草稿和手动 Timer；失败/十秒超时保持打开；慢 I/O 只占一个槽；保存期间变化会取消退出；失败弹窗激活应用并可导出文本与未发送草稿 | 故障测试覆盖首次懒加载、失败、重试、超时、单次回复；现有内容测试继续覆盖真实编辑器。OS 强杀无法保证最后一个未落盘编辑，磁盘内核操作也不能被 Swift 强制取消 |
| R02 诊断 | 统一大小写子系统与音频模块，导出兼容旧名称；Release 保留 warning/error；严重日志按代码位置每分钟限流并计数；动态内容为 private；诊断快照附构建/权限/服务状态；日志 32 MiB，崩溃报告最多 8 份、单份 4 MiB、总计 16 MiB、最近七天；生成新 zip 后原子导出 | 测试覆盖 predicate、128 个位置上限、崩溃报告年龄/数量/软链接过滤和构建身份。历史日志、Apple 崩溃报告可能含路径，不能把整个支持包宣称为已去标识化 |
| R03 进程阻塞 | Focus 初始扫描、键盘 fallback、网络名称查询、录屏查询和终端命令统一有界捕获；并发排空两条管道；直接子进程退出后的继承管道只有一秒宽限；停止长流 TERM 后有 KILL 宽限；键盘读写移到串行工作队列并合并；音频停止不阻塞 UI | 继承管道测试和原有进程/传输测试通过。不可中断内核/设备操作仍是系统边界，避免重复排队而非宣称能强制中止所有内核调用 |
| R04 自动验证 | `Tools/verify-stability.py` 使用独立 bundle ID、偏好域与内容目录，执行原生及合成 fixture；命令有 deadline，超时回收自建进程组；失败也留 xcresult 摘要；CI 运行该入口与 Release 构建，覆盖全部活动 PR 分支 | 本地执行有记录；GitHub hosted CI 尚未触发。UI 自动化目标和实际设备操作不混入单元测试 |
| R05 服务恢复 | AgentBridge、Now Playing 使用六次退避恢复（1/2/4/8/16/30 秒）；连续健康一分钟才重置预算；失败状态准确，停止取消重试，旧 generation 回调被丢弃；Now Playing 同时处理 EOF/进程退出 | 覆盖预算、稳定连接复位、失败启动后停止、迟到 ready；真实私有适配器兼容性仍须真机测。预算耗尽后通过关闭/重新开启相关功能或重新启动应用恢复 |
| R06 重启交接 | Bridge discovery 有跨进程锁与 owner；旧实例不能删除新端口/auth；退出不再重复写内容；非 Shelf 临时文件按实例隔离，只清理自身或确认已退出实例；Shelf 附件继续保留 | 双 owner 交接和两实例临时文件测试通过。独立启动两个完整 Atoll 并同时编辑相同文档仍不属于受支持使用方式 |
| R07 私有接口 | 原生 HUD 共存；取消暂停、启动、轮询 OSDUIHelper；旧 OSD guardian 不再构建进应用。Now Playing 仅监督自己启动的子进程 | 视觉行为改变：某些键操作可同时出现原生 HUD 与 Atoll HUD。推荐选项的异步偏好问题未收到回复后，按稳定性优先执行并告知。详见 [ADR-002](decisions/002-stability-boundaries.md)。旧系统/多屏/音频仍需验收 |
| R08 线程/所有权 | CF Create 返回值正确消费 retained 所有权；通知/计时器到主 actor 的边界明确；deinit 不捕获自身到异步任务；音频控制在串行队列、显示值在主 actor、实时音频只使用 bridge 的 atomic 值；CoreAudio 泛型只接受 BitwiseCopyable | ASAN 全量和 TSAN 故障套件通过；未测真实音频 render 回调。仅有锁/队列保护已经确认的类型标记 unchecked Sendable，未用它掩盖 UI 隔离 |
| R09 产物身份 | 每次构建写 `BuildInfo.json`：commit、dirty、源码/依赖 SHA-256、Xcode、SDK、配置、版本；CI 固定 Xcode 26.3；构建显式只使用已提交 Package.resolved | 测试验证指纹存在；验证记录另含主二进制 SHA-256。当前机器为 Xcode 27，不能把本机通过当作 hosted Xcode 26.3 通过 |
| R10 恢复语义 | Agent 未发送草稿本地恢复（64 份、每份 64 KiB、文本总计 1 MiB），迟到加载不覆盖新编辑；手动 Timer 保留原 deadline/暂停剩余时间，过期旧 Timer 静默清理；不改变 Clock 所有权；损坏/超额恢复文件保留并显示错误 | 覆盖草稿恢复、新编辑胜出、坏/超额文件不覆盖、Timer 编解码与暂停。快照和 previous 是单次恢复辅助，不是长期历史备份 |
| R11 资源/组合场景 | HTTP 流式接收最多 2 MiB，超时/取消回收任务；Stats 卷详情跳过网络卷，继续单个后台刷新；增加只读资源采样工具，输出最多两份 8 MiB JSONL、PID 消失或复用即停 | 超大 chunked body、卡住的响应、原有资源探针通过；采样器仅做自建 sleep 的三点 smoke。尚未把真实 Atoll 的 24–72 小时曲线记为通过 |
| R12 维护成本 | 仅提取 save gate、retry、lease、recovery、HTTP、diagnostics 和进程监督这些必要边界，保留原生架构与既有 UI 系统 | 没有进行大文件全量重构。架构说明、决策和本表作为后续修改入口 |

## 验证记录

最终结果与构建指纹见[本轮验证记录](audit/2026-10-10-stability-fixes/verification.json)。原始 xcresult 与大日志保留在记录指定的本机临时路径；文档目录保留摘要、命令、警告和失败修正记录。

- 新增 16 个故障测试；原有 311 个原生测试共同组成 327 个全量用例。
- 最终 Debug/Release 构建和全量 327 个原生测试通过；Python 7 个、Agent/RPC 16 组、插件 7 个、旧 guardian 4 个、子进程 supervisor 3 个通过。Release 留有 34 条弃用/未使用等警告；未出现本轮处理的 actor/Sendable/指针所有权警告，不宣称零编译警告。
- ASAN 全量 326 通过；首次有一个固定 50 ms 的编辑器布局等待失败，改为等待编辑器真实出现，保留失败记录再全量通过。
- TSAN 故障套件最终 16 通过，没有 data-race 报告。Sanitizer 环境记录了 CFNetwork 初始化时的优先级告警，完整保留；不把测试通过写成零运行时告警。
- 合成 Agent/RPC、插件、旧 guardian、拥有的子进程监督、UTF-8/取消/会话预算探针均有独立记录。它们不代表真实外部 Agent 的版本兼容性。
- 第一份安装版启动通过，但首次退出把未打开内容区的加载误判为编辑而取消退出；内容保留，未强杀。修复了加载等待，并加上 `testFirstQuitAwaitsLazyRestorationBeforeDetectingEdits`；[初次失败记录](audit/2026-10-10-stability-fixes/first-installed-quit-failure.json)继续保留。
- Sanitizer 记录对应各自测试时的源码状态。ASAN 326 是首次退出加载修正之前的全量结果；最终 327 普通回归、16 TSAN、Release 和安装验收覆盖该修正，没有把先前 sanitizer 结果伪装成最终每个字节都被执行过。
- 最终安装版的第一次标准 Quit 已通过，原有 Extra Space 内容逐字节哈希一致，并已重新启动。本机开发签名、安装、运行路径/指纹和短时启动采样已验证；完整 UI/音频/亮度/锁屏组合、发布签名/公证、Instruments 和 hosted CI 尚未执行。

## 固定调试入口

从项目目录运行全量回归；每次输出单独记录，测试不会替换安装版：

```sh
python3 Tools/verify-stability.py
python3 Tools/verify-stability.py --native-only --only-tests StabilityHardeningTests
python3 Tools/verify-stability.py --sanitizer address --native-only
python3 Tools/verify-stability.py --sanitizer thread --native-only --only-tests StabilityHardeningTests
```

`--skip-build` 只用于已确认对应源码和 sanitizer 配置的现成产物。失败先读该次 `native-summary.log` 与 `native.log`，保留同一份 xcresult；修正原因后新建一次输出目录复跑，不覆盖失败证据。

调试一项问题时，先记录动作、时间、使用的产物 SHA-256 与 BuildInfo，再重复一个最短场景。例如：编辑 → Quit → 写盘失败；服务掉线 → 重连 → 关闭功能；开 Stats → 关闭 → 休眠 → 唤醒。抓住同一次故障对应的日志和 trace，再改最小边界，跑相关回归，最后跑全量。

退出保存失败可先导出 `Atoll Recovery.json`。它包含 Extra Space 和未发送 Agent 草稿，保存到用户选择的位置，文件权限 0600。Shelf 持久化错误会保留原文件或 recovery 副本；不要通过清空文件绕过失败提示。

## 内容位置与恢复

| 内容 | 生产位置（相对用户目录） | 恢复方式 |
| --- | --- | --- |
| Extra Space | `Library/Application Support/Atoll/ExtraSpace/content.txt` | 编辑器的恢复/导出入口；旁边 `.previous` 是前一份快照 |
| Shelf | `Library/Application Support/DynamicIsland/Shelf/items.json` | 保留的 `items.recovery-*.json`；附件继续依赖原文件或 Atoll Shelf 临时目录 |
| Agent 缓存/草稿 | `Library/Application Support/Atoll/AgentBridge/sessions.json`、`drafts.json` | 缓存不是原始 transcript；草稿恢复有预算，损坏时保留文件并显示错误 |
| 手动 Timer | `Library/Application Support/Atoll/timer.json` | 自动恢复未到期 Timer；已到期不重播提醒；Clock Timer 由 Clock 管理 |

损坏恢复文件需要先复制留档、检查 `.previous` 或导出的内容。关闭应用后，再用已验证的备份恢复；重新启动完成加载。不要在两个运行实例同时写文件。恢复是明确操作，程序不会无声覆盖唯一残留。

## 长期运行的验收方式

先选择将要验收的同一份 Release 二进制，记录 BuildInfo 和二进制 hash；本轮已用原团队的本机开发证书签名并安装，尚未做分发公证。安装签名会改变主二进制 hash，记录中保留构建、签名后和安装后三个身份。下面的采样只接受用户指定的该进程 PID：

```sh
python3 Tools/monitor-stability.py --pid 12345 --hours 24 --interval 10 --output /tmp/atoll-soak-24h
```

脚本不读取命令参数、文件名称、用户内容或凭据；记录 CPU、RSS、FD 数与直接子进程数。PID 被复用时停止，以免拼接另一进程的数据。`12345` 必须替换为实际验收进程，不能借此把旧安装版的指标归给本轮代码。

按以下顺序验收，并保留每阶段的时间和结果：

1. 空闲基线：暖机后关掉面板，记录至少十分钟。打开/关闭各功能后返回相同空闲状态，比较曲线是否回落。
2. 高频交互：重复打开/关闭 Stats、切页、编辑/撤销/保存、Shelf 导入/移除、Timer 开始/暂停/停止；FD、子进程和保留对象应回到可解释的稳定范围。
3. 系统组合：多屏插拔、AirPods/有线输出切换、锁屏/解锁、休眠跨 Timer 到期、离线/重新联网、权限运行中撤销；确认降级、重新授权和取消路径。
4. 内容故障：只在独立测试账户/合成目录验证磁盘满、只读、卷断开、损坏文件、异常退出及恢复。确认唯一残留没有被空状态覆盖。
5. 24 小时，再到 72 小时：回到相同空闲状态比较 RSS/CPU/FD/子进程趋势。不要把 warm-up、缓存上限内增长、sanitizer 开销当作泄漏，也不要忽略持续增长。

发现持续增长或卡顿，用 Instruments 的 Allocations/Leaks/Time Profiler 对准同一产物和同一最短场景。先定位保留链、主线程等待或重复任务，再设具体预算；当前没有实测完整设备矩阵，因此不虚构“稳定空闲 CPU/RSS”数字。

验收记录至少包含：二进制/源码身份、硬件/OS、场景、时间、预期、实际、日志/trace 路径和 verdict。全部目标系统与设备场景通过后，才适合给该产物“长期稳定”标签。

工具链依据：[Apple SwiftPM CI 指南](https://developer.apple.com/documentation/xcode/building-swift-packages-or-apps-that-use-them-in-continuous-integration-workflows)、[GitHub macos-26 镜像工具清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)。日志隐私依据：[Apple OSLogPrivacy](https://developer.apple.com/documentation/os/oslogprivacy)。
