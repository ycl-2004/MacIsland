# YC Island：首次使用与权限审计

日期：2026-10-17。范围：当前源代码、Debug/Release 配置、启动与设置界面。未读取本机 TCC 数据库，也未变更系统授权。本轮开始前已有 Shelf 修复，保留原改动。

## 需求与交付

1. 初始页和首次使用流程体现 YC Island，而非上游产品的欢迎页。
2. 逐项确认权限仍由哪些功能使用，区分按需保留和不需要开启。
3. 修复过度请求、误导说明和影响首次使用的逻辑。
4. 保留已有数据、系统授权身份、用户设置和上游署名。
5. 用构建、回归检查和原生页面渲染提供证据。
6. 后续用户明确要求将新版替换到 `/Applications/Atoll.app`；保留旧版备份并确认启动。

## 新的首次使用流程

欢迎页 → 权限指南 → 开始使用。界面使用现有 SwiftUI/macOS 控件、语义颜色和一枚 YC 岛形标记；英文、简体、繁体均有新文案。权限页可以滚动，不直接申请任何权限，也不检查受保护文件夹。减少动态效果设置下不播放转场动画。

欢迎页介绍音乐、计时器、笔记、Shelf 和已连接的 Agent；删除原作者图片、Atoll 欢迎文案以及指向上游隐私政策的按钮。内置“数据与权限”说明明确本地数据和联网功能的区别，尤其是主动发送的屏幕图片和问题会交给所选 Agent/服务商。原有 About 上游署名、NOTICE 和许可证保留。

不再强制选择职业预设，也不在欢迎页自动弹出 DevTools 模式选择。重看指南不会应用预设或覆盖功能开关。菜单新增“Welcome to YC Island”，完成页可直接进入 Feature Management。

引导完成状态单独保存为 `ycIslandOnboardingCompleted`。自动启动引导时先记录未完成；只有“开始使用”或“自定义设置”才完成。刘海欢迎动画写入 `firstLaunch = false` 不再导致未完成的新引导被跳过。既有安装沿用旧的已完成状态，不强制重跑。

`CFBundleDisplayName`、欢迎窗口、设置入口及权限用途说明使用 YC Island。可执行文件/产物仍叫 `Atoll.app`，bundle IDs 和存储路径不改，避免在本轮引入偏好数据与系统授权的迁移。系统某些列表仍可能显示旧产物名；彻底改包名属于单独迁移。

## 当前权限结论

基础笔记、内置计时器、Shelf 的文字和链接不要求下表权限。保留声明不代表用户必须授权。

| 权限 | 当前调用位置/用途 | 建议 |
| --- | --- | --- |
| 辅助功能 Accessibility | `MediaKeyInterceptor` 媒体键；`SystemTimerBridge` 读取/控制系统时钟；`MenuBarLayout` 和 `FullscreenMediaDetection` 查询其他应用 UI | 使用这些整合时开；普通刘海窗口、笔记和内置计时器无需全开。已取消媒体键监控启动时自动申请，设置和菜单仍能主动申请 |
| 屏幕录制 | `ScreenQuestionManager.capture()` 主动圈选截图；Color Picker 屏幕取色 | 使用圈选提问/取色时开。截图发出前由用户提交问题；不能把该功能描述为“所有内容只在本机” |
| 系统音频采集 | `AudioTap` 和 `AppVolumeTap` 的 Core Audio process taps | 实时波形和单 App 音量调整需要；与麦克风录音分开，保留 `NSAudioCaptureUsageDescription` |
| 相机 | `WebcamManager` 的 live mirror | 使用镜子时开；欢迎流程不再提前申请，保留 camera entitlement/用途说明 |
| 日历 | `CalendarService.requestFullAccessToEvents()` 读取日程 | 使用日程展示时开。EventKit 读取既有事件需要 full access，没有只读授权级别；write-only 无法读取，现可升级请求 |
| 提醒事项 | `requestFullAccessToReminders()`；`setReminderCompleted()` 写入完成状态 | 单独可选。只开日历或只开提醒事项都能进入相应设置，不再强制两者同时授权 |
| 文件与文件夹 | Shelf 用户添加的文件；`DownloadManager` 监控下载目录 | 按实际文件/目录授权。删除“文稿 + 下载都必须可读”的 Shelf 开关限制，以及开设置页时的目录探测；Shelf 不需要完整磁盘访问 |
| 位置 | `LockScreenWeatherLocationProvider` 天气定位 | 当地天气按需开；移除管理器初始化、App 启动和显示天气面板时的申请。锁屏设置有主动请求入口；用户打开天气开关仍可请求。未授权时具体回退依天气供应商而定 |
| 蓝牙 | `BluetoothAudioManager`，包括 `CBCentralManager` 的 BLE 电量读取 | 需要设备连接/电量显示时保留。相关功能默认启用，仍可能由实际设备访问触发系统提示；本轮不重写该监控链 |
| 自动化 Automation | Apple Music/AirPlay、支持的终端、`ScreenRecordingManager` 的 System Events 控制 | 按实际控制的目标 App 分别授权，保留 hardened-runtime Apple Events entitlement。不是所有 Agent 集成都需要所有目标权限 |
| Apple Music / Media & Apple Music | `AnimatedArtworkManager` 的 MusicKit 授权与动态封面 | 仅动态封面按需开；不同于 Automation，不是普通播放状态和所有音乐控件的通用前提 |
| 完整磁盘访问 FDA | `DoNotDisturbManager` 读取受保护的自定义 Focus 配置 | 通常不开；仅自定义专注名称、图标、颜色等元数据需要。基本 Focus 检测有回退。移除 Shelf 的 FDA 推广入口并重写说明 |
| Developer Tools | Focus 的可选 unified-log 检测模式 | 默认 `.withoutDevTools` 可用，通常不开；删除首次引导强制选择，保留高级菜单入口 |
| 麦克风 | 未发现 `AVAudioRecorder`、音频输入录制或语音提问入口；`MicrophoneMonitor` 只观察设备使用状态 | 删除旧的语音提问麦克风用途声明；不新增麦克风 entitlement |
| 通讯录、照片库、通知、语音识别、单独的输入监控 | 未发现本轮审计相关的授权申请入口 | 不建议为了启动应用而开启；不新增声明。媒体键走现有 Accessibility 路径 |

下载监听和蓝牙等已启用功能仍可能在实际访问时触发系统提示；本轮只保证引导本身不批量申请，不宣称整个应用永远没有启动期提示。

## 配置清理

- Debug/Release 的权限用途说明统一为 YC Island，并描述具体功能；Desktop 从错误的“保存截图”改为 Shelf 文件（圈选提问实际写临时目录）。
- 移除没有录音入口支撑的 `NSMicrophoneUsageDescription`。
- 最低 App target 为 macOS 14.6，EventKit 使用 macOS 14 的 full-access API；移除旧 `NSCalendarsUsageDescription` / `NSRemindersUsageDescription`，保留两条 full-access 声明。土耳其语 InfoPlist 也同步更新旧声明和品牌。
- App Sandbox 已关闭；移除无效的 `com.apple.security.temporary-exception.apple-events`，保留 hardened-runtime 的 `com.apple.security.automation.apple-events`。
- Camera、Calendars、Location 资源能力仍有调用。`disable-library-validation` 涉及现有 framework/动态加载路径，本轮保留，不把它当成用户隐私开关。
- 未更换 bundle ID、签名团队或安装路径；未重置系统权限。首次审计完成后，按用户后续明确指示替换了 `/Applications/Atoll.app`，详见下方安装记录。

## Apple 依据

- [EventKit 访问事件库](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)：events/reminders 分别请求 full access。
- [EventKit macOS 14 API 迁移](https://developer.apple.com/documentation/technotes/tn3153-adopting-api-changes-for-eventkit-in-ios-macos-and-watchos)：新授权 API 与用途声明。
- [macOS 文件访问控制](https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web)：受保护目录和完整磁盘访问是不同的授权范围。
- [App Sandbox temporary exception](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html)：该例外为沙盒 Apple Events 访问而设。

## 验证及限制

证据见 [审计附件](audit/2026-10-17-onboarding-permissions/README.md)。实际授予/拒绝 TCC、带正式签名应用的系统权限弹窗、外接相机、蓝牙硬件、系统时钟和第三方终端整合需要在对应环境手动验证。自动化检查不使用真实 Agent、不点击系统授权，也不读取用户私有日历和文件。

## 用户授权后的安装

按用户后续指示，已用同一份已通过测试的 Release 产物替换 `/Applications/Atoll.app`，并启动完成。签名沿用原开发证书与团队，deep/strict 校验通过；安装二进制哈希与签名后的暂存包一致，源码与最终测试/构建的身份一致。

旧进程通过正常退出请求结束，未强制终止。原退出监视器超时后，独立的新 NSWorkspace 查询和进程检查均确认旧进程已消失，才进行替换。安装前后笔记文件哈希一致；安装器未写用户偏好或系统授权。

旧版备份：`/Users/yichenlin/Desktop/Tester/Atoll/Build/InstalledBackups/Onboarding-20261017-202236-5967fc9d/OriginalAtoll.app`。新版运行 PID：`15841`。完整证据见 [安装回执](audit/2026-10-17-onboarding-permissions/installation.json)。安装与启动成功不代表所有系统授权/硬件功能已完成交互验收。
