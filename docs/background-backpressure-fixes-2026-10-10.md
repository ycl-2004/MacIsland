# 后台通信与保存背压修复

日期：2026-10-10。承接 [资源审查](background-resource-review-2026-10-10.md) 中 R1/P1 和 R2/P2；用户追加要求在验证通过后替换 `/Applications/Atoll.app`。

## 修改

- `CodexRPCClient` 的所有发送（JSONL、WebSocket、握手、pong、审批回复）改走 `CodexPipeWriter`。DispatchIO 异步执行实际写入；只交给 channel 一份 active frame，其余由有界 FIFO 管理。完整 frame 最大 512 KiB，active + waiting 总计最大 1 MiB / 64 份，同时最多 64 个未完成 RPC。
- 请求超时/取消会删除尚未开始写入的 frame；active frame 可能写到一半，因此中止 channel 并断连，避免后续 frame 混入残缺消息。回复和通知也有 12 秒写入 deadline。丢失确认时保留原有不确定交付语义，不自动重发 prompt。
- channel 拥有单独、原子设置 close-on-exec 的 descriptor，cleanup 后释放；按 descriptor 禁止 SIGPIPE。关闭 client 沿用 `ProcessRunner.terminateOwned`：先正常停止自己创建的 reader/proxy，250ms 后仍未退出再清理，不操作外部终端的 daemon。
- `AgentSessionStore` 与 `ExtraSpaceStore` 共用 `LatestSnapshotWriter`：只入队一个 drain，保留正在写入的一份和可替换的最新待写快照。自动保存、立即保存、同步测试 barrier 和异步退出保存都经过这个入口。
- Extra Space 的 debounce task 只捕获弱引用和延迟，不捕获整份旧文本。旧 revision 的完成回调不会清除新内容的 dirty 状态；保存失败仍保留草稿并可重试。恢复前一版本会丢弃尚未开始的待写快照。

取舍：保存采用最新状态语义，中间尚未写入的 revision 会被替换；前一版本仍由实际落盘写入维护。通信取消如果发生在 active write 上，会关闭连接；已有发送结果仍需通过终端确认。

实现依据：Apple 的 [DispatchIO 写入](https://developer.apple.com/documentation/dispatch/dispatch_io_write)、[channel close](https://developer.apple.com/documentation/dispatch/dispatch_io_close) 和 [libdispatch 官方头文件](https://github.com/apple/swift-corelibs-libdispatch/blob/main/dispatch/io.h)。`.stop` 对进行中的 I/O 是尽力中止，调用返回后仍可能收到 completion；generation/stopped 检查会忽略这些旧回调。descriptor 的 `F_SETNOSIGPIPE` / `F_DUPFD_CLOEXEC` 依据 [Apple XNU fcntl 文档](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/man/man2/fcntl.2)。

## 验证

- 最终 Debug build-for-testing 成功，**340 个原生测试通过，0 失败、0 跳过**；xcresult runtimeWarnings 为空。新加 6 项专项测试覆盖快照生命周期数量、恢复丢弃 pending、frame 字节/数量上限、队列取消、写入 deadline 和断管 SIGPIPE。
- 全部 Python、Agent/RPC 合成回归、插件队列、历史 guardian 和 owned supervisor 用例通过。新增 RPC 用例覆盖并发 frame 不交错、请求取消、重连及拒绝 SIGTERM 的 owned child 最终退出。
- 最终有效输入 2,621 个家庭 emoji / 65,525 UTF-8 bytes：150ms 请求 timeout 实际 **160ms** 返回，最大 MainActor 心跳间隔 **14.2ms**。修复前同一探针约 3 秒返回，心跳约 3 秒停顿。最终合成回归另测约 153ms / 13.1ms。
- 首次磁盘写入阻塞时，Agent 连续 12 次更新：实际落盘由 **13 次降为 2 次**。Extra Space 48 次约 1 MiB 编辑：RSS 增量由 **50.1 MiB 降为 4.2 MiB**，仍只落盘首尾 2 次；解除阻塞后两份文件都保留最新内容。
- 快照生命周期测试在 writer 阻塞期间提交 1,000 次不同对象：保留数量严格为 **2**，解除阻塞后只写 `[0, 1000]`。这个检查直接验证引用释放，避免把 allocator 的 RSS 缓存误判为快照积压。

完整原始结果在 `Build/VerificationRuns/background-fix-final-20261010`、`background-fix-rpc-final-20261010-v2` 和 `background-fix-slow-save-20261010-v2`。前一次完整验证也通过；初次受沙箱限制的构建及探针 harness 编译失败已保留，调整后重跑成功。已有其他源码的编译警告未在本轮清理。

本轮测试均使用合成 Agent 端和临时文件，没有调用真实 Agent CLI。没有做 ASAN/TSAN、真实会话发送、睡眠/多屏或 24–72 小时 soak，不能把本轮结果当作全部长期场景已验收。

## 安装

最终 Release 已替换到 `/Applications/Atoll.app` 并启动，PID **80956**；签名团队仍为 `BQYHJCCRMP`。安装版源码指纹为 `8c2b6bb119509675e436f024e4808f631f2e64e58856639fdb7ea4131b7b18ad`，与最终测试源码一致。原生 Quit 菜单退出后确认旧实例消失再替换；初次退出辅助程序报错，没有继续修改安装目录，切换原生退出流程后成功。没有强制终止应用。

旧应用保留在 `Build/InstalledBackups/BackgroundBackpressure-20261010-215110-7ef755d6/OriginalAtoll.app`，二进制指纹核对一致；Extra Space 在旧版完成保存后的内容指纹与新版启动后相同。签名、源码指纹、正常退出、原应用备份与内容保留记录归档到 [修复证据目录](audit/2026-10-10-background-backpressure-fixes/README.md)。

安装后约一分钟采样：13 个点，进程持续运行，FD 保持 29、直接子进程保持 3；启动期 RSS 128.0–183.6 MiB。之后一次只读计数显示 RSS 142.9 MiB、physical footprint 71.0 MiB。启动期缓存变化使这段 RSS 不能与之前已经运行较久的采样直接比较；该 smoke 检查只支持成功启动和短时资源数量稳定，不证明无慢泄漏。
