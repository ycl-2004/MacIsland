# Shelf 错误与响应速度修复 · 2026-10-17

本轮按用户要求，只修复错误和已测到的性能开销。没有增加搜索、固定、撤销、采集入口或新快捷键，代码修复阶段没有安装、提交或发布；后续按用户授权完成安装，见下文。

## 修复内容

| 问题 | 修改后的行为 |
| --- | --- |
| 刘海已打开在其他页时，入口接受 drop 却不导入 | 入口和 Shelf 面板调用同一接收函数；实际入队才返回成功，同时切到 Shelf。已打开的 Extra Space 编辑器保留自己的拖放，不切页。关闭功能、自己的拖出、框选期间和队列超限会拒绝接收。 |
| 文件在外部改名后拖出使用旧路径 | 拖出前在后台解析书签并检查当前文件，合并更新缓存路径。不会触发挂载或授权弹窗；不可用、已经移除或取消的项目不会启动迟到的拖拽。 |
| 慢 provider 拖住整批，用户没有反馈 | 接收时立即显示总数及已完成数；全局最多 3 个 provider 并行，结果按完成顺序追加，16 ms 合并一次界面更新。清空和关闭功能会取消队列，旧回调不能回填。 |
| 关闭 Shelf 后数量提示仍显示 | 独立提示和音乐旁的次级提示均检查响应式功能开关；保留原有暂存内容。 |
| 长文本拖拽预览、200 项列表和批量移除耗时偏高 | 标签限制为 256 个 Unicode scalar 加省略号，完整拖出文本不变；卡片按需创建；多项移除只发布一次列表变更。 |

原有文件和文本容量限制、取消语义、临时副本保护、十分钟成功交接宽限期均保留。没有新增“取消/重试”按钮；本轮复用已有提示、清空和功能开关。

惰性列表的框选按完整列表计算，包含未显示的项目。回归测试曾发现长距离滚动后有 8 px 偏差；将间距纳入每个固定宽度单元后修正。实际 AppKit 卡片坐标已对照验证，覆盖左右两种布局。

## 性能对照

同一机器、Debug 隔离测试宿主、同样的 680 × 170 pt Shelf 布局。基线见 [原评估](shelf-assessment-2026-10-17.md)，本轮原始结果见 [证据目录](audit/2026-10-17-shelf-fixes/README.md)。这些是局部耗时，不是端到端 FPS 保证。

| 检查 | 修复前 | 修复后 |
| --- | --- | --- |
| 200 项首次同步布局 | 约 265 ms | 21.1 ms |
| 200 项时 AppKit 视图子树数量 | 421 | 27 |
| 200 项全选同步更新 | 约 29.4 ms | 1.8 ms |
| 1 MiB 文本拖拽预览，3 次采样 | 约 29–39 ms | 0.57–1.32 ms |
| 移除 200 项 | 约 27–28 ms，200 次发布 | 0.17 ms，1 次发布 |
| 注入 600 ms 慢 provider 后的快速项目 | 首批约 605–612 ms；150 ms 时 0 项 | 两个快速项目约 18.6 ms；150 ms 时已有 2 项和进度提示 |

50 个本地小文件的底层顺序解析探针本轮为 265 ms，主 actor 最大采样间隔 6.1 ms；基线为 189–231 ms / 6.1–6.4 ms。这条兼容接口仍用于其他调用方，本轮没有声称其吞吐量提高。Shelf 的并发调度单独用受控慢 provider 验证。

## 验证与边界

- 原有 `ShelfTests`：26 项通过，覆盖持久化、文件交接、清理、provider 取消及缩略图限制。
- 新增 `ShelfReliabilityTests`：14 项通过，覆盖接收回调、并发/容量限制、清空/关闭后的迟到回调、文件改名、取消、完整文本载荷、一次批量发布、提示开关及真实惰性视图坐标。
- 原有关闭/持久化/清空回归：1 项通过。合计 41 项回归通过。
- 性能诊断 5 项通过；原生拖拽窗口收到 `Renamed-test.txt`，文件仍存在、项目仍保留、拖拽状态已结束。接收区只读取本地拖拽载荷，不上传或复制到第三方。
- Debug 测试构建与 Release 构建均通过。

本轮不覆盖 Finder、浏览器、NAS/断开的网络卷、多屏幕和休眠唤醒的完整交互矩阵，也没有测量持续拖动的逐帧延迟。临时原生拖拽探针已归档，避免它进入自动测试后等待人工操作。桌面工具在读取测试窗口时延迟，并重新打开了测试副本；该副本及其子进程和唯一偏好域已清理。

## 安装结果

按用户后续授权，已将同一份 Release 修复版替换到 `/Applications/Atoll.app`，并启动完成（核验 PID 5158）。安装前通过原生 Quit 正常退出；签名沿用原开发证书与团队，安装后 deep/strict 验证通过，二进制 SHA-256 与签名后的构建一致。

旧版保存在 `Build/InstalledBackups/ShelfFix-20261017-194122-0d1942bc/OriginalAtoll.app`，旧版二进制哈希核对一致。完整记录见 [安装回执](audit/2026-10-17-shelf-fixes/installation.json)。安装启动通过不代表 Finder、浏览器、网络卷等完整交互矩阵已验收。

## 参考

- [Apple：Improving app responsiveness](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
- [Apple：Creating performant scrollable stacks](https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks)
- [Apple：NSView.beginDraggingSession](https://developer.apple.com/documentation/appkit/nsview/begindraggingsession(with:event:source:))
- [Apple：BookmarkResolutionOptions](https://developer.apple.com/documentation/foundation/nsurl/bookmarkresolutionoptions)
