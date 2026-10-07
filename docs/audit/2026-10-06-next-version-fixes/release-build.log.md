# Signed Release build and signature

Final build exit: 0. Signature verification exit: 0.
Full log: `/tmp/atoll-next-version-fixes/release-verified-build.log`.

```sh
xcodebuild build -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -configuration Release -destination 'platform=macOS' -derivedDataPath Build \
  -clonedSourcePackagesDirPath Build/SourcePackages \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=68E2393709CD7141C4791351A029F486D4E7E60E \
  DEVELOPMENT_TEAM=BQYHJCCRMP
codesign --verify --deep --strict --verbose=2 Build/Release/Atoll.app
```

## Build warnings

```text
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/audio/AudioTap.swift:170:17: warning: capture of 'self' with non-Sendable type 'AudioTap?' in a '@Sendable' closure [#SendableClosureCaptures]
    |                 `- warning: capture of 'self' with non-Sendable type 'AudioTap?' in a '@Sendable' closure [#SendableClosureCaptures]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Notch/NotchExtraSpaceView.swift:16:36: warning: main actor-isolated static property 'shared' can not be referenced from a nonisolated context; this is an error in the Swift 6 language mode
    |                                    `- warning: main actor-isolated static property 'shared' can not be referenced from a nonisolated context; this is an error in the Swift 6 language mode
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Notch/NotchHomeView.swift:1085:10: warning: 'onChange(of:perform:)' was deprecated in macOS 14.0: Use `onChange` with a two or zero parameter action closure instead. [#DeprecatedDeclaration]
     |          `- warning: 'onChange(of:perform:)' was deprecated in macOS 14.0: Use `onChange` with a two or zero parameter action closure instead. [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Notch/NotchHomeView.swift:1097:10: warning: 'onChange(of:perform:)' was deprecated in macOS 14.0: Use `onChange` with a two or zero parameter action closure instead. [#DeprecatedDeclaration]
     |          `- warning: 'onChange(of:perform:)' was deprecated in macOS 14.0: Use `onChange` with a two or zero parameter action closure instead. [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Onboarding/OnboardingView.swift:146:31: warning: result of call to 'requestAccess()' is unused [#NoUsage]
    |                               `- warning: result of call to 'requestAccess()' is unused [#NoUsage]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Onboarding/SparkleView.swift:73:13: warning: initialization of immutable value 'area' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]
   |             `- warning: initialization of immutable value 'area' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Onboarding/SparkleView.swift:74:13: warning: immutable value 'baseBirthRate' was never used; consider replacing with '_' or removing it [#NoUsage]
   |             `- warning: immutable value 'baseBirthRate' was never used; consider replacing with '_' or removing it [#NoUsage]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Settings/SettingsView.swift:6276:9: warning: using '_' to ignore the result of a Void-returning function is redundant
     |         `- warning: using '_' to ignore the result of a Void-returning function is redundant
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Settings/SettingsView.swift:6283:9: warning: using '_' to ignore the result of a Void-returning function is redundant
     |         `- warning: using '_' to ignore the result of a Void-returning function is redundant
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Settings/SettingsView.swift:6290:9: warning: using '_' to ignore the result of a Void-returning function is redundant
     |         `- warning: using '_' to ignore the result of a Void-returning function is redundant
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Settings/SettingsView.swift:6303:9: warning: using '_' to ignore the result of a Void-returning function is redundant
     |         `- warning: using '_' to ignore the result of a Void-returning function is redundant
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Shelf/Models/ShelfItem.swift:149:35: warning: 'icon(forFileType:)' was deprecated in macOS 12.0: Use -[NSWorkspace iconForContentType:] instead. [#DeprecatedDeclaration]
    |                                   `- warning: 'icon(forFileType:)' was deprecated in macOS 12.0: Use -[NSWorkspace iconForContentType:] instead. [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Shelf/ViewModels/ShelfItemViewModel.swift:616:31: warning: main actor-isolated property 'indexOfSelectedItem' can not be referenced from a nonisolated context
    |                               `- warning: main actor-isolated property 'indexOfSelectedItem' can not be referenced from a nonisolated context
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Shelf/ViewModels/ShelfItemViewModel.swift:622:31: warning: call to main actor-isolated instance method 'validateVisibleColumns()' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                               `- warning: call to main actor-isolated instance method 'validateVisibleColumns()' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Shelf/ViewModels/ShelfItemViewModel.swift:623:48: warning: main actor-isolated property 'directoryURL' can not be referenced from a nonisolated context
    |                                                `- warning: main actor-isolated property 'directoryURL' can not be referenced from a nonisolated context
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Shelf/ViewModels/ShelfItemViewModel.swift:624:31: warning: main actor-isolated property 'directoryURL' can not be mutated from a nonisolated context
    |                               `- warning: main actor-isolated property 'directoryURL' can not be mutated from a nonisolated context
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Shelf/ViewModels/ShelfStateViewModel.swift:94:26: warning: capture of 'persistence' with non-Sendable type 'ShelfPersistenceService' in a '@Sendable' closure [#SendableClosureCaptures]
    |                          `- warning: capture of 'persistence' with non-Sendable type 'ShelfPersistenceService' in a '@Sendable' closure [#SendableClosureCaptures]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Timer/RulerTimerPicker.swift:158:17: warning: initialization of immutable value 'mid' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]
    |                 `- warning: initialization of immutable value 'mid' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/Agents/AgentEventServer.swift:266:59: warning: capture of 'self' with non-Sendable type 'AgentEventServer' in a '@Sendable' closure [#SendableClosureCaptures]
    |                                                           `- warning: capture of 'self' with non-Sendable type 'AgentEventServer' in a '@Sendable' closure [#SendableClosureCaptures]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/Agents/ProcessRunner.swift:96:59: warning: 'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope [#ImplicitStrongCapture]
    |                                                           |- warning: 'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope [#ImplicitStrongCapture]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/Agents/ProcessRunner.swift:105:61: warning: 'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope [#ImplicitStrongCapture]
    |                                                             |- warning: 'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope [#ImplicitStrongCapture]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/BluetoothAudioManager.swift:41:60: warning: main actor-isolated static property 'shared' can not be referenced from a nonisolated context; this is an error in the Swift 6 language mode
     |                                                            `- warning: main actor-isolated static property 'shared' can not be referenced from a nonisolated context; this is an error in the Swift 6 language mode
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/BluetoothAudioManager.swift:929:20: warning: value 'refreshedLevel' was defined but never used; consider replacing with boolean test [#NoUsage]
     |                    `- warning: value 'refreshedLevel' was defined but never used; consider replacing with boolean test [#NoUsage]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/CalendarManager.swift:154:19: warning: call to main actor-isolated instance method 'handleEventStoreChanged()' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'handleEventStoreChanged()' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/KeyboardBrightnessSensor.swift:88:51: warning: 'kIOMasterPortDefault' was deprecated in macOS 12.0: renamed to 'kIOMainPortDefault' [#DeprecatedDeclaration]
    |                                                   |- warning: 'kIOMasterPortDefault' was deprecated in macOS 12.0: renamed to 'kIOMainPortDefault' [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/KeyboardBrightnessSensor.swift:104:42: warning: treating a forced downcast to 'CFNumber' as optional will never produce 'nil'
    |                                 |        `- warning: treating a forced downcast to 'CFNumber' as optional will never produce 'nil'
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/KeyboardBrightnessSensor.swift:136:51: warning: 'kIOMasterPortDefault' was deprecated in macOS 12.0: renamed to 'kIOMainPortDefault' [#DeprecatedDeclaration]
    |                                                   |- warning: 'kIOMasterPortDefault' was deprecated in macOS 12.0: renamed to 'kIOMainPortDefault' [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/LockScreenDisplayContextProvider.swift:103:19: warning: call to main actor-isolated instance method 'refresh(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'refresh(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/LockScreenDisplayContextProvider.swift:112:19: warning: call to main actor-isolated instance method 'refresh(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'refresh(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/LockScreenDisplayContextProvider.swift:120:19: warning: call to main actor-isolated instance method 'refresh(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'refresh(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/LockScreenLiveActivityWindowManager.swift:151:19: warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/LockScreenLiveActivityWindowManager.swift:160:19: warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/LockScreenManager.swift:163:90: warning: trailing closure in this context is confusable with the body of the statement; pass as a parenthesized argument to silence this warning
    |                                                                                          `- warning: trailing closure in this context is confusable with the body of the statement; pass as a parenthesized argument to silence this warning
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/LockScreenManager.swift:174:92: warning: trailing closure in this context is confusable with the body of the statement; pass as a parenthesized argument to silence this warning
    |                                                                                            `- warning: trailing closure in this context is confusable with the body of the statement; pass as a parenthesized argument to silence this warning
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/LockScreenReminderWidgetPanelManager.swift:181:19: warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/LockScreenReminderWidgetPanelManager.swift:190:19: warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/LockScreenTimerWidgetManager.swift:307:19: warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/LockScreenTimerWidgetManager.swift:316:19: warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/LockScreenWeatherManager.swift:750:13: warning: initialization of immutable value 'usesMetric' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]
     |             `- warning: initialization of immutable value 'usesMetric' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/LockScreenWeatherPanelManager.swift:174:19: warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/LockScreenWeatherPanelManager.swift:183:19: warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'handleScreenGeometryChange(reason:)' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/MicrophoneMonitor.swift:70:27: warning: 'kAudioObjectPropertyElementMaster' was deprecated in macOS 12.0: renamed to 'kAudioObjectPropertyElementMain' [#DeprecatedDeclaration]
    |                           |- warning: 'kAudioObjectPropertyElementMaster' was deprecated in macOS 12.0: renamed to 'kAudioObjectPropertyElementMain' [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/MicrophoneMonitor.swift:161:23: warning: 'kAudioObjectPropertyElementMaster' was deprecated in macOS 12.0: renamed to 'kAudioObjectPropertyElementMain' [#DeprecatedDeclaration]
    |                       |- warning: 'kAudioObjectPropertyElementMaster' was deprecated in macOS 12.0: renamed to 'kAudioObjectPropertyElementMain' [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/MicrophoneMonitor.swift:188:23: warning: 'kAudioObjectPropertyElementMaster' was deprecated in macOS 12.0: renamed to 'kAudioObjectPropertyElementMain' [#DeprecatedDeclaration]
    |                       |- warning: 'kAudioObjectPropertyElementMaster' was deprecated in macOS 12.0: renamed to 'kAudioObjectPropertyElementMain' [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/MicrophoneMonitor.swift:205:23: warning: 'kAudioObjectPropertyElementMaster' was deprecated in macOS 12.0: renamed to 'kAudioObjectPropertyElementMain' [#DeprecatedDeclaration]
    |                       |- warning: 'kAudioObjectPropertyElementMaster' was deprecated in macOS 12.0: renamed to 'kAudioObjectPropertyElementMain' [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/MicrophoneMonitor.swift:233:23: warning: 'kAudioObjectPropertyElementMaster' was deprecated in macOS 12.0: renamed to 'kAudioObjectPropertyElementMain' [#DeprecatedDeclaration]
    |                       |- warning: 'kAudioObjectPropertyElementMaster' was deprecated in macOS 12.0: renamed to 'kAudioObjectPropertyElementMain' [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/MicrophoneMonitor.swift:286:23: warning: 'kAudioObjectPropertyElementMaster' was deprecated in macOS 12.0: renamed to 'kAudioObjectPropertyElementMain' [#DeprecatedDeclaration]
    |                       |- warning: 'kAudioObjectPropertyElementMaster' was deprecated in macOS 12.0: renamed to 'kAudioObjectPropertyElementMain' [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/MusicManager.swift:33:9: warning: immutable property will not be decoded because it is declared with an initial value which cannot be overwritten
     |         |- warning: immutable property will not be decoded because it is declared with an initial value which cannot be overwritten
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/MusicManager.swift:2028:17: warning: no 'async' operations occur within 'await' expression [#UnnecessaryEffectMarker]
     |                 `- warning: no 'async' operations occur within 'await' expression [#UnnecessaryEffectMarker]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/ReminderLiveActivityManager.swift:173:13: warning: no 'async' operations occur within 'await' expression [#UnnecessaryEffectMarker]
    |             `- warning: no 'async' operations occur within 'await' expression [#UnnecessaryEffectMarker]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/ReminderLiveActivityManager.swift:222:13: warning: no 'async' operations occur within 'await' expression [#UnnecessaryEffectMarker]
    |             `- warning: no 'async' operations occur within 'await' expression [#UnnecessaryEffectMarker]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/SiriVisibilityMonitor.swift:67:19: warning: main actor-isolated property 'isDisplayOn' can not be mutated from a Sendable closure
    |                   `- warning: main actor-isolated property 'isDisplayOn' can not be mutated from a Sendable closure
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/SiriVisibilityMonitor.swift:68:19: warning: call to main actor-isolated instance method 'updateMonitoringState()' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'updateMonitoringState()' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/SiriVisibilityMonitor.swift:71:19: warning: main actor-isolated property 'isDisplayOn' can not be mutated from a Sendable closure
    |                   `- warning: main actor-isolated property 'isDisplayOn' can not be mutated from a Sendable closure
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/SiriVisibilityMonitor.swift:72:19: warning: call to main actor-isolated instance method 'updateMonitoringState()' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'updateMonitoringState()' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/SiriVisibilityMonitor.swift:77:19: warning: main actor-isolated property 'isInLowPowerMode' can not be mutated from a Sendable closure
    |                   `- warning: main actor-isolated property 'isInLowPowerMode' can not be mutated from a Sendable closure
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/SiriVisibilityMonitor.swift:78:19: warning: call to main actor-isolated instance method 'updateMonitoringState()' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                   `- warning: call to main actor-isolated instance method 'updateMonitoringState()' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/SiriVisibilityMonitor.swift:154:23: warning: call to main actor-isolated instance method 'checkSiriVisibility()' in a synchronous nonisolated context [#ActorIsolatedCall]
    |                       `- warning: call to main actor-isolated instance method 'checkSiriVisibility()' in a synchronous nonisolated context [#ActorIsolatedCall]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/StatsManager.swift:742:27: warning: reference to captured var 'self' in concurrently-executing code; this is an error in the Swift 6 language mode [#SendableClosureCaptures]
     |                           `- warning: reference to captured var 'self' in concurrently-executing code; this is an error in the Swift 6 language mode [#SendableClosureCaptures]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/SystemHUDManager.swift:176:14: warning: capture of 'self' in a closure that outlives deinit; this is an error in the Swift 6 language mode
    |              `- warning: capture of 'self' in a closure that outlives deinit; this is an error in the Swift 6 language mode
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/WebcamManager.swift:142:81: warning: 'externalUnknown' was deprecated in macOS 14.0: renamed to 'AVCaptureDevice.DeviceType.external' [#DeprecatedDeclaration]
    |                                                                                 |- warning: 'externalUnknown' was deprecated in macOS 14.0: renamed to 'AVCaptureDevice.DeviceType.external' [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/WebcamManager.swift:171:89: warning: 'externalUnknown' was deprecated in macOS 14.0: renamed to 'AVCaptureDevice.DeviceType.external' [#DeprecatedDeclaration]
    |                                                                                         |- warning: 'externalUnknown' was deprecated in macOS 14.0: renamed to 'AVCaptureDevice.DeviceType.external' [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/models/DynamicIslandViewModel.swift:300:47: warning: converting non-Sendable function value to '@MainActor @Sendable @convention(block) () -> Void' may introduce data races
    |                                               `- warning: converting non-Sendable function value to '@MainActor @Sendable @convention(block) () -> Void' may introduce data races
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/models/FeaturePermissionSnapshot.swift:21:68: warning: 'authorized' was deprecated in macOS 14.0: Check for full access or write only access [#DeprecatedDeclaration]
   |                                                                    `- warning: 'authorized' was deprecated in macOS 14.0: Check for full access or write only access [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/models/PickedColor.swift:24:9: warning: immutable property will not be decoded because it is declared with an initial value which cannot be overwritten
    |         |- warning: immutable property will not be decoded because it is declared with an initial value which cannot be overwritten
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/private/CGSSpace.swift:54:13: warning: initialization of immutable value 'flag' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]
   |             `- warning: initialization of immutable value 'flag' was never used; consider replacing with assignment to '_' or removing it [#NoUsage]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/utils/AppleHardwareInfo.swift:129:44: warning: 'kIOMasterPortDefault' was deprecated in macOS 12.0: renamed to 'kIOMainPortDefault' [#DeprecatedDeclaration]
    |                                            |- warning: 'kIOMasterPortDefault' was deprecated in macOS 12.0: renamed to 'kIOMainPortDefault' [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/utils/AppleHardwareInfo.swift:159:44: warning: 'kIOMasterPortDefault' was deprecated in macOS 12.0: renamed to 'kIOMainPortDefault' [#DeprecatedDeclaration]
    |                                            |- warning: 'kIOMasterPortDefault' was deprecated in macOS 12.0: renamed to 'kIOMainPortDefault' [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/utils/CPUSensorCollector.swift:52:13: warning: result of call to 'IOReportCreateSamples' is unused [#NoUsage]
    |             `- warning: result of call to 'IOReportCreateSamples' is unused [#NoUsage]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/utils/SMC.swift:158:47: warning: 'kIOMasterPortDefault' was deprecated in macOS 12.0: renamed to 'kIOMainPortDefault' [#DeprecatedDeclaration]
    |                                               |- warning: 'kIOMasterPortDefault' was deprecated in macOS 12.0: renamed to 'kIOMainPortDefault' [#DeprecatedDeclaration]
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/AudioRouteManager.swift:218:88: warning: forming 'UnsafeMutableRawPointer' to a variable of type 'CFString'; this is likely incorrect because 'CFString' may contain an object reference.
    |                                                                                        `- warning: forming 'UnsafeMutableRawPointer' to a variable of type 'CFString'; this is likely incorrect because 'CFString' may contain an object reference.
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/SystemMediaControllers.swift:580:86: warning: forming 'UnsafeMutableRawPointer' to a variable of type 'T'; this is likely incorrect because 'T' may contain an object reference.
    |                                                                                      `- warning: forming 'UnsafeMutableRawPointer' to a variable of type 'T'; this is likely incorrect because 'T' may contain an object reference.
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/SystemMediaControllers.swift:596:85: warning: forming 'UnsafeRawPointer' to a variable of type 'T'; this is likely incorrect because 'T' may contain an object reference.
    |                                                                                     `- warning: forming 'UnsafeRawPointer' to a variable of type 'T'; this is likely incorrect because 'T' may contain an object reference.
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/SystemMediaControllers.swift:612:76: warning: forming 'UnsafeMutableRawPointer' to a variable of type 'T'; this is likely incorrect because 'T' may contain an object reference.
    |                                                                            `- warning: forming 'UnsafeMutableRawPointer' to a variable of type 'T'; this is likely incorrect because 'T' may contain an object reference.
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/SystemMediaControllers.swift:622:75: warning: forming 'UnsafeRawPointer' to a variable of type 'T'; this is likely incorrect because 'T' may contain an object reference.
    |                                                                           `- warning: forming 'UnsafeRawPointer' to a variable of type 'T'; this is likely incorrect because 'T' may contain an object reference.
2026-10-06 21:08:49.347 appintentsmetadataprocessor[57973:6272413] warning: Metadata extraction skipped, no AppIntents.framework dependency found
```

## Completion excerpt

```text
[#ImplicitStrongCapture]: <https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-capture>
[#NoUsage]: <https://docs.swift.org/compiler/documentation/diagnostics/no-usage>
[#SendableClosureCaptures]: <https://docs.swift.org/compiler/documentation/diagnostics/sendable-closure-captures>
[#UnnecessaryEffectMarker]: <https://docs.swift.org/compiler/documentation/diagnostics/unnecessary-effect-marker>

SwiftDriver\ Compilation\ Requirements DynamicIsland normal arm64 com.apple.xcode.tools.swift.compiler (in target 'DynamicIsland' from project 'DynamicIsland')
    cd /Users/yichenlin/Desktop/Tester/Atoll

Copy /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.swiftmodule/arm64-apple-macos.abi.json /Users/yichenlin/Desktop/Tester/Atoll/Build/Intermediates.noindex/DynamicIsland.build/Release/DynamicIsland.build/Objects-normal/arm64/Atoll.abi.json (in target 'DynamicIsland' from project 'DynamicIsland')
    cd /Users/yichenlin/Desktop/Tester/Atoll
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -resolve-src-symlinks -rename /Users/yichenlin/Desktop/Tester/Atoll/Build/Intermediates.noindex/DynamicIsland.build/Release/DynamicIsland.build/Objects-normal/arm64/Atoll.abi.json /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.swiftmodule/arm64-apple-macos.abi.json

Copy /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.swiftmodule/Project/arm64-apple-macos.swiftsourceinfo /Users/yichenlin/Desktop/Tester/Atoll/Build/Intermediates.noindex/DynamicIsland.build/Release/DynamicIsland.build/Objects-normal/arm64/Atoll.swiftsourceinfo (in target 'DynamicIsland' from project 'DynamicIsland')
    cd /Users/yichenlin/Desktop/Tester/Atoll
    builtin-copy -exclude .DS_Store -exclude CVS -exclude .svn -exclude .git -exclude .hg -resolve-src-symlinks -rename /Users/yichenlin/Desktop/Tester/Atoll/Build/Intermediates.noindex/DynamicIsland.build/Release/DynamicIsland.build/Objects-normal/arm64/Atoll.swiftsourceinfo /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.swiftmodule/Project/arm64-apple-macos.swiftsourceinfo

Ld /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app/Contents/MacOS/Atoll normal (in target 'DynamicIsland' from project 'DynamicIsland')
    cd /Users/yichenlin/Desktop/Tester/Atoll

GenerateDSYMFile /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app.dSYM /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app/Contents/MacOS/Atoll (in target 'DynamicIsland' from project 'DynamicIsland')
    cd /Users/yichenlin/Desktop/Tester/Atoll
    /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/dsymutil /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app/Contents/MacOS/Atoll -o /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app.dSYM

CopySwiftLibs /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app (in target 'DynamicIsland' from project 'DynamicIsland')
    cd /Users/yichenlin/Desktop/Tester/Atoll
    builtin-swiftStdLibTool --copy --verbose --sign 68E2393709CD7141C4791351A029F486D4E7E60E --scan-executable /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app/Contents/MacOS/Atoll --scan-folder /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app/Contents/Frameworks --scan-folder /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app/Contents/PlugIns --scan-folder /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app/Contents/Library/SystemExtensions --scan-folder /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app/Contents/Extensions --scan-folder /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/Accelerate.framework --scan-folder /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/IOKit.framework --scan-folder /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/ApplicationServices.framework --platform macosx --toolchain /var/run/com.apple.security.cryptexd/mnt/com.apple.MobileAsset.MetalToolchain-v27.1.266.1.uQ9dAp/Metal.xctoolchain --toolchain /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain --destination /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app/Contents/Frameworks --strip-bitcode --strip-bitcode-tool /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/bitcode_strip --emit-dependency-info /Users/yichenlin/Desktop/Tester/Atoll/Build/Intermediates.noindex/DynamicIsland.build/Release/DynamicIsland.build/SwiftStdLibToolInputDependencies.dep --filter-for-swift-os --back-deploy-swift-span

ExtractAppIntentsMetadata (in target 'DynamicIsland' from project 'DynamicIsland')
    cd /Users/yichenlin/Desktop/Tester/Atoll
2026-10-06 21:08:49.340 appintentsmetadataprocessor[57973:6272413] Starting appintentsmetadataprocessor export
2026-10-06 21:08:49.347 appintentsmetadataprocessor[57973:6272413] warning: Metadata extraction skipped, no AppIntents.framework dependency found

CodeSign /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app (in target 'DynamicIsland' from project 'DynamicIsland')
    cd /Users/yichenlin/Desktop/Tester/Atoll

    Signing Identity:     "Apple Development: yichen.lin.2004@gmail.com (5AGX9CFNPL)"

    /usr/bin/codesign --force --sign 68E2393709CD7141C4791351A029F486D4E7E60E -o runtime --entitlements /Users/yichenlin/Desktop/Tester/Atoll/Build/Intermediates.noindex/DynamicIsland.build/Release/DynamicIsland.build/Atoll.app.xcent --timestamp\=none --generate-entitlement-der /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app

Validate /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app (in target 'DynamicIsland' from project 'DynamicIsland')
    cd /Users/yichenlin/Desktop/Tester/Atoll
    builtin-validationUtility /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app -no-validate-extension -infoplist-subpath Contents/Info.plist

RegisterWithLaunchServices /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app (in target 'DynamicIsland' from project 'DynamicIsland')
    cd /Users/yichenlin/Desktop/Tester/Atoll
    builtin-lsregisterurl --record-path /Users/yichenlin/Desktop/Tester/Atoll/Build/Intermediates.noindex/XCBuildData/registered-launchservices.txt -- /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app

PruneExplicitPrecompiledModules /Users/yichenlin/Desktop/Tester/Atoll/Build/Intermediates.noindex/ExplicitPrecompiledModules

PruneExplicitPrecompiledModules /Users/yichenlin/Desktop/Tester/Atoll/Build/SDKExplicitPrecompiledModules

PruneExplicitPrecompiledModules /Users/yichenlin/Desktop/Tester/Atoll/Build/Intermediates.noindex/SwiftExplicitPrecompiledModules

** BUILD SUCCEEDED **

```

## Signature

```text
--prepared:/Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app/Contents/Frameworks/Lottie.framework/Versions/Current/.
--validated:/Users/yichenlin/Desktop/Tester/Atoll/Build/Release/Atoll.app/Contents/Frameworks/Lottie.framework/Versions/Current/.
Build/Release/Atoll.app: valid on disk
Build/Release/Atoll.app: satisfies its Designated Requirement

```
