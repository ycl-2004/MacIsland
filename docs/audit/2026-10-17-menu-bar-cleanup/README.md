# Atoll 菜单栏测试残留清理 — 2026-10-17

用户要求：解释“Allow in the Menu Bar”为何有大量 Atoll，并清理测试残留。

## 结果

- 初始 Launch Services 清单识别出 85 个 Atoll 根应用注册，其中 56 个使用独立测试身份，另有旧开发构建和安装备份。它们并不代表有 85 个进程正在运行。
- 按核对清单注销 82 条旧注册，全部返回成功；删除仍在磁盘上的 43 份隔离测试 `.app`。测试结果、日志、源码、当前 Debug/Release 和安装备份文件均保留。
- 清理后根应用注册只剩 `/Applications/Atoll.app`、`Build/Release/Atoll.app` 和 `Build/Debug/Atoll.app`，对应 production 和 `.dev` 两种 bundle ID。
- 最后重新打开系统设置的 Menu Bar 页面，验证 `Allow in the Menu Bar` 标题存在，并读到 2 个独立 Atoll 静态标签元素；先前相同探针读到 25 次 Atoll 标签匹配。没有点击许可开关。
- 保留的两种注册身份与 production/development 构建一致；AX 界面本身没有公开每个条目的 bundle ID，不能仅凭相同显示名称逐条作更强的身份断言。
- 正式安装版 deep/strict 签名校验通过，二进制 SHA-256 与本轮前的安装回执一致。没有替换安装版或改动应用数据、偏好、TCC 权限。

## 原因和防复发修复

`Tools/verify-stability.py` 原先为每次 XCTest 创建随机 bundle ID，测试结束只清理偏好。`DynamicNotchApp` 在测试宿主里仍创建 `MenuBarExtra`，因此系统同时积累了应用注册与菜单栏历史。

本轮修改：

1. 在 XCTest/XCUITest 模式下将菜单栏 `isInserted` 固定为 false，普通运行继续使用原用户设置。依据 [Apple MenuBarExtra 文档](https://developer.apple.com/documentation/swiftui/menubarextra/init%28isinserted%3Acontent%3Alabel%3A%29)。
2. 临时宿主显示名改为 `YC Island Tests`，便于识别。
3. 测试结束在 `finally` 中注销临时 App；成功时删除宿主 `.app`，保留 `.xcresult`、日志及其他测试产物。失败宿主保留，方便调试。（后续 Shelf 审计改为成功时删除整个复制的 `host` 目录，约 85 MB/次；`.xcresult` 与日志不在其中，仍保留。）

已通过完整 Debug build-for-testing 和 6 项 OnboardingPermissionTests。成功运行后核对：临时 App 不存在、随机 bundle ID 已从注册记录消失、结果包仍在。该修复属于测试执行路径，不需要覆盖日常使用的安装版。

## 证据

| 文件 | 内容 |
| --- | --- |
| `registration-before.json` / `registration-after.json` | 清理前后定向应用注册 |
| `plan.json` / `cleanup.json` | 核对清单及每项执行结果 |
| `verification.json` | 正式安装版完整性和清理后验证 |
| `ui-final.log` / `ui-final.json` | 实际系统设置页面标签和 AX 路径 |
| `build.log` / `native.summary.json` / `steps.json` | 成功构建、6 项测试结果 |
| `new-test-host-cleanup.json` | 新测试宿主的自动注销/删除和结果保留 |
| `initial-build-failed.log` | 中间实现失败记录；已修正，未作为通过证据 |

初版尝试在 SceneBuilder 内使用运行时 if/else，编译器不支持；已改为受支持的 `isInserted` binding，随后重新构建和测试通过。

没有重置整个 Launch Services、Background Task Management 或 Control Center，也没有编辑私有系统数据库。系统菜单栏容器的直接读取被 macOS 隐私保护拒绝，未绕过；实际清理通过定向 `lsregister -u` 和测试宿主删除完成，界面通过标准辅助功能读取核验。重启系统服务和注销用户均未执行。

未来若重新运行旧的测试 App，或手动打开原生备份包，macOS 仍可能再次注册它们。失败宿主需要继续调试时应使用修复后的源码；不能保证旧二进制不创建入口。

未执行 commit、push 或发布。
