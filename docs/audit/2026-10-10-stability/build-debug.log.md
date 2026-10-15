# Debug build receipt

```sh
xcodebuild -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Debug -destination 'platform=macOS' -derivedDataPath Build -disableAutomaticPackageResolution CODE_SIGNING_ALLOWED=NO build-for-testing
```

```text
** TEST BUILD SUCCEEDED **
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/components/Notch/NotchExtraSpaceView.swift:16:36: warning: main actor-isolated static property 'shared' can not be referenced from a nonisolated context; this is an error in the Swift 6 language mode
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIsland/managers/BluetoothAudioManager.swift:41:60: warning: main actor-isolated static property 'shared' can not be referenced from a nonisolated context; this is an error in the Swift 6 language mode
```

Warnings are existing code/toolchain diagnostics. Incremental Debug and optimized Release warning counts are not comparable.
