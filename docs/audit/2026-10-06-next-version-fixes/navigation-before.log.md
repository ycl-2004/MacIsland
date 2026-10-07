# Failing coordinator regression before setter guard

```text
Command line invocation:
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test-without-building -xctestrun /tmp/atoll-next-version-fixes/native-final/DynamicIsland.xctestrun -destination platform=macOS -resultBundlePath /tmp/atoll-next-version-fixes/native-final-results.xcresult

Writing result bundle at path:
	/tmp/atoll-next-version-fixes/native-final-results.xcresult

--- xcodebuild: WARNING: Using the first of multiple matching destinations:
{ platform:macOS, arch:arm64e, id:00008132-001A681436D3801C, name:My Mac }
{ platform:macOS, arch:arm64, id:00008132-001A681436D3801C, name:My Mac }
{ platform:macOS, arch:x86_64, id:00008132-001A681436D3801C, name:My Mac }
{ platform:macOS, arch:arm64e, variant:Mac Catalyst, id:00008132-001A681436D3801C, name:My Mac }
{ platform:macOS, arch:arm64, variant:Mac Catalyst, id:00008132-001A681436D3801C, name:My Mac }
{ platform:macOS, arch:x86_64, variant:Mac Catalyst, id:00008132-001A681436D3801C, name:My Mac }
{ platform:macOS, arch:arm64e, variant:DriverKit, id:00008132-001A681436D3801C, name:My Mac }
{ platform:macOS, arch:arm64, variant:DriverKit, id:00008132-001A681436D3801C, name:My Mac }
{ platform:macOS, arch:arm64e, variant:Designed for [iPad,iPhone], id:00008132-001A681436D3801C, name:My Mac }
{ platform:macOS, arch:arm64, variant:Designed for [iPad,iPhone], id:00008132-001A681436D3801C, name:My Mac }
2026-10-06 21:02:31.716951-0700 Atoll[56295:6257916] ✅ Fullscreen status: ["Built-in Retina Display": false]
2026-10-06 21:02:31.782577-0700 Atoll[56295:6257916] [plugin] AddInstanceForFactory: No factory registered for id <CFUUID 0x766f340100> F8BB1C28-BAE8-11D6-9C31-00039315CD46
2026-10-06 21:02:31.884337-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884370-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884388-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884403-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884417-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884430-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884444-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884457-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884471-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884610-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884636-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884655-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884674-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884755-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884771-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884784-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884796-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884808-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884819-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884830-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884840-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884851-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884861-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884872-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884883-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884948-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884960-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884971-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884981-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.884991-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885002-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885059-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885073-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885084-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885095-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885106-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885117-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885153-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885165-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885176-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885186-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885197-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885208-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885243-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885255-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885265-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885275-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885285-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885296-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885342-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885353-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885364-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885374-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885385-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885395-0700 Atoll[56295:6257916] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=241785183928321, rateLimit=32hz }
2026-10-06 21:02:31.885468-0700 Atoll[56295:6257916] [carc] Reporter disconnected or already stopped. { func=stop, reporterID=241785183928321 }
2026-10-06 21:02:31.962751-0700 Atoll[56295:6257916] [] CMIO_DAL_CMIOExtension_Device.mm:373:Device legacy uuid isn't present, using new style uuid instead
2026-10-06 21:02:32.155396-0700 Atoll[56295:6258090] [] warning: failed to mark memory(GRAPHICS) error 0x8 ((os/kern) no access)
2026-10-06 21:02:32.177743-0700 Atoll[56295:6258090] fopen failed for data file: errno = 2 (No such file or directory)
2026-10-06 21:02:32.545685-0700 Atoll[56295:6258092] fopen failed for data file: errno = 2 (No such file or directory)
Test Suite 'Selected tests' started at 2026-10-06 21:02:32.572.
Test Suite 'DynamicIslandTests.xctest' started at 2026-10-06 21:02:32.573.
Test Suite 'ContentReliabilityTests' started at 2026-10-06 21:02:32.573.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testAgentMemoryKeepsOnlyRecentBoundedCards]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testAgentMemoryKeepsOnlyRecentBoundedCards]' passed (0.025 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testAgentSnapshotBudgetReloadsLargeMultiSessionHistory]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testAgentSnapshotBudgetReloadsLargeMultiSessionHistory]' passed (0.185 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testExplicitRecoveryKeepsTheCurrentVersion]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testExplicitRecoveryKeepsTheCurrentVersion]' passed (0.026 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testExtraSpaceRejectsOversizedChangesWithoutReplacingContent]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testExtraSpaceRejectsOversizedChangesWithoutReplacingContent]' passed (0.094 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testFailedTimerSoundImportLeavesPreviousSound]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testFailedTimerSoundImportLeavesPreviousSound]' passed (0.004 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testOversizedExtraSpaceFileIsKeptAndNotLoadedOrOverwritten]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testOversizedExtraSpaceFileIsKeptAndNotLoadedOrOverwritten]' passed (0.016 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testRecoveryWritesEvenWhenThePreviousTextMatchesTheCurrentDraft]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testRecoveryWritesEvenWhenThePreviousTextMatchesTheCurrentDraft]' passed (0.058 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testRepeatedSaveKeepsPreviousVersionAndPrivatePermissions]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testRepeatedSaveKeepsPreviousVersionAndPrivatePermissions]' passed (0.015 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testSharedContentUsesIsolatedTestPaths]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testSharedContentUsesIsolatedTestPaths]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testShelfOwnedCopyHasAByteBudgetAndPrivatePermissions]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testShelfOwnedCopyHasAByteBudgetAndPrivatePermissions]' passed (0.002 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testZipSnapshotsInputsAndPreservesSingleFileName]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testZipSnapshotsInputsAndPreservesSingleFileName]' passed (0.015 seconds).
Test Suite 'ContentReliabilityTests' passed at 2026-10-06 21:02:33.018.
	 Executed 11 tests, with 0 failures (0 unexpected) in 0.441 (0.445) seconds
Test Suite 'ExtraSpaceTests' started at 2026-10-06 21:02:33.018.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testAutosaveCoalescesEditsAndImmediateSaveKeepsTheNewestText]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testAutosaveCoalescesEditsAndImmediateSaveKeepsTheNewestText]' passed (0.294 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testDoubleClickAndCommandSSwitchTheRealTabBetweenEditingAndReading]' started.
2026-10-06 21:02:33.557139-0700 Atoll[56295:6258089] [Common] Unable to obtain a task name port right for pid 413: (os/kern) failure (0x5)
2026-10-06 21:02:33.703843-0700 Atoll[56295:6257916] [CursorUI] ViewBridge to RemoteViewService Terminated: Error Domain=com.apple.ViewBridge.error Code=18 "(null)" UserInfo={com.apple.ViewBridge.error.hint=this process disconnected remote view controller -- benign unless unexpected, com.apple.ViewBridge.error.description=NSViewBridgeErrorCanceled}
Test Case '-[DynamicIslandTests.ExtraSpaceTests testDoubleClickAndCommandSSwitchTheRealTabBetweenEditingAndReading]' passed (0.621 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testExtraSpaceUsesTheSameDefaultHeightAsOtherMainTabs]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testExtraSpaceUsesTheSameDefaultHeightAsOtherMainTabs]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testKeyboardUndoReachesTheFocusedNativeEditor]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testKeyboardUndoReachesTheFocusedNativeEditor]' passed (0.363 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testLongNativeEditorRestoresSelectionAndScrollPositionAfterRemount]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testLongNativeEditorRestoresSelectionAndScrollPositionAfterRemount]' passed (0.262 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testNativeTypingCompositionAndUndoUpdateTheSameDocument]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testNativeTypingCompositionAndUndoUpdateTheSameDocument]' passed (0.110 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testSaveEndsEditingAndReadingSwipeClosesWithoutScrollingOrEditing]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testSaveEndsEditingAndReadingSwipeClosesWithoutScrollingOrEditing]' passed (0.135 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testSaveFailureRetainsTheDraftAndCanBeRetried]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testSaveFailureRetainsTheDraftAndCanBeRetried]' passed (0.026 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testTabAndSettingsRenderWithTheExistingVisualSystem]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testTabAndSettingsRenderWithTheExistingVisualSystem]' passed (0.443 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testTerminationFlushAndReopeningPreserveUnicodeAndNewlines]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testTerminationFlushAndReopeningPreserveUnicodeAndNewlines]' passed (0.026 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testToolbarPasteIsOneUndoableEdit]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testToolbarPasteIsOneUndoableEdit]' passed (0.112 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testTwoEditorsShareTextWithoutKeepingInvalidUndoRanges]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testTwoEditorsShareTextWithoutKeepingInvalidUndoRanges]' passed (0.095 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testUnreadableDocumentCannotBeOverwrittenByAnEmptyEditor]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testUnreadableDocumentCannotBeOverwrittenByAnEmptyEditor]' passed (0.025 seconds).
Test Suite 'ExtraSpaceTests' passed at 2026-10-06 21:02:35.536.
	 Executed 13 tests, with 0 failures (0 unexpected) in 2.513 (2.517) seconds
Test Suite 'LightweightPolicyTests' started at 2026-10-06 21:02:35.536.
Test Case '-[DynamicIslandTests.LightweightPolicyTests testBackgroundStatsResumeAfterUnlockButDoNotColdStart]' started.
2026-10-06 21:02:35.677499-0700 Atoll[56295:6257916] [debug] 🔍 [2026-10-07T04:02:35.677Z] [StatsManager.swift:191] startMonitoring() - StatsManager: Starting monitoring...
🔍 [2026-10-07T04:02:35.677Z] [StatsManager.swift:191] startMonitoring() - StatsManager: Starting monitoring...
2026-10-06 21:02:35.680901-0700 Atoll[56295:6257916] [debug] 🔍 [2026-10-07T04:02:35.681Z] [StatsManager.swift:214] startMonitoring() - StatsManager: Monitoring started
🔍 [2026-10-07T04:02:35.681Z] [StatsManager.swift:214] startMonitoring() - StatsManager: Monitoring started
2026-10-06 21:02:35.680970-0700 Atoll[56295:6257916] [debug] 🔍 [2026-10-07T04:02:35.681Z] [StatsManager.swift:227] stopMonitoring() - StatsManager: Monitoring stopped
🔍 [2026-10-07T04:02:35.681Z] [StatsManager.swift:227] stopMonitoring() - StatsManager: Monitoring stopped
2026-10-06 21:02:35.681227-0700 Atoll[56295:6257916] [debug] 🔍 [2026-10-07T04:02:35.681Z] [StatsManager.swift:191] startMonitoring() - StatsManager: Starting monitoring...
🔍 [2026-10-07T04:02:35.681Z] [StatsManager.swift:191] startMonitoring() - StatsManager: Starting monitoring...
2026-10-06 21:02:35.684406-0700 Atoll[56295:6257916] [debug] 🔍 [2026-10-07T04:02:35.684Z] [StatsManager.swift:214] startMonitoring() - StatsManager: Monitoring started
🔍 [2026-10-07T04:02:35.684Z] [StatsManager.swift:214] startMonitoring() - StatsManager: Monitoring started
2026-10-06 21:02:35.685079-0700 Atoll[56295:6257916] [debug] 🔍 [2026-10-07T04:02:35.685Z] [StatsManager.swift:227] stopMonitoring() - StatsManager: Monitoring stopped
🔍 [2026-10-07T04:02:35.685Z] [StatsManager.swift:227] stopMonitoring() - StatsManager: Monitoring stopped
Test Case '-[DynamicIslandTests.LightweightPolicyTests testBackgroundStatsResumeAfterUnlockButDoNotColdStart]' passed (0.150 seconds).
Test Case '-[DynamicIslandTests.LightweightPolicyTests testConnectionRefreshSlowsWithoutDisablingEvents]' started.
Test Case '-[DynamicIslandTests.LightweightPolicyTests testConnectionRefreshSlowsWithoutDisablingEvents]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.LightweightPolicyTests testFeatureManagementDestinationRendersInTheSettingsWindow]' started.
Test Case '-[DynamicIslandTests.LightweightPolicyTests testFeatureManagementDestinationRendersInTheSettingsWindow]' passed (0.857 seconds).
Test Case '-[DynamicIslandTests.LightweightPolicyTests testPresetRoundTripAndShelfExclusion]' started.
Test Case '-[DynamicIslandTests.LightweightPolicyTests testPresetRoundTripAndShelfExclusion]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.LightweightPolicyTests testPresetUndoProtectsManualEditsIncludingRoundTrips]' started.
Test Case '-[DynamicIslandTests.LightweightPolicyTests testPresetUndoProtectsManualEditsIncludingRoundTrips]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.LightweightPolicyTests testRealDefaultsTransactionRejectsStalePreviewAndPreservesLaterEdits]' started.
Test Case '-[DynamicIslandTests.LightweightPolicyTests testRealDefaultsTransactionRejectsStalePreviewAndPreservesLaterEdits]' passed (0.011 seconds).
Test Case '-[DynamicIslandTests.LightweightPolicyTests testStatsGateAndBackgroundCadence]' started.
Test Case '-[DynamicIslandTests.LightweightPolicyTests testStatsGateAndBackgroundCadence]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.LightweightPolicyTests testStatsStartsFromPublishedVisibilityAndStopsWhenHidden]' started.
2026-10-06 21:02:36.560390-0700 Atoll[56295:6257916] [debug] 🔍 [2026-10-07T04:02:36.560Z] [StatsManager.swift:191] startMonitoring() - StatsManager: Starting monitoring...
🔍 [2026-10-07T04:02:36.560Z] [StatsManager.swift:191] startMonitoring() - StatsManager: Starting monitoring...
2026-10-06 21:02:36.565159-0700 Atoll[56295:6257916] [debug] 🔍 [2026-10-07T04:02:36.565Z] [StatsManager.swift:214] startMonitoring() - StatsManager: Monitoring started
🔍 [2026-10-07T04:02:36.565Z] [StatsManager.swift:214] startMonitoring() - StatsManager: Monitoring started
2026-10-06 21:02:36.565253-0700 Atoll[56295:6257916] [debug] 🔍 [2026-10-07T04:02:36.565Z] [StatsManager.swift:227] stopMonitoring() - StatsManager: Monitoring stopped
🔍 [2026-10-07T04:02:36.565Z] [StatsManager.swift:227] stopMonitoring() - StatsManager: Monitoring stopped
Test Case '-[DynamicIslandTests.LightweightPolicyTests testStatsStartsFromPublishedVisibilityAndStopsWhenHidden]' passed (0.008 seconds).
Test Suite 'LightweightPolicyTests' passed at 2026-10-06 21:02:36.567.
	 Executed 8 tests, with 0 failures (0 unexpected) in 1.028 (1.031) seconds
Test Suite 'NextVersionReliabilityTests' started at 2026-10-06 21:02:36.567.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testCalendarServiceOnlyQueriesForDemandAndPreservesReminderConsumer]' started.
2026-10-06 21:02:36.587111-0700 Atoll[56295:6257916] [lifecycle] 🔄 [2026-10-07T04:02:36.587Z] [CalendarManager.swift:449] updateEvents(force:) - CalendarManager: Updating events (force: false)
🔄 [2026-10-07T04:02:36.587Z] [CalendarManager.swift:449] updateEvents(force:) - CalendarManager: Updating events (force: false)
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testCalendarServiceOnlyQueriesForDemandAndPreservesReminderConsumer]' passed (0.134 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testCoordinatorRoutesDisabledCurrentRememberedAndShortcutTargets]' started.
2026-10-06 21:02:43.422014-0700 Atoll[56405:6258887] ✅ Fullscreen status: ["Built-in Retina Display": false]
2026-10-06 21:02:43.460245-0700 Atoll[56405:6258887] [plugin] AddInstanceForFactory: No factory registered for id <CFUUID 0x778716fd80> F8BB1C28-BAE8-11D6-9C31-00039315CD46
2026-10-06 21:02:43.524336-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.524370-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.524388-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.524404-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.524418-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.524432-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.524445-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.524459-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.524472-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.524733-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.524749-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.524763-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.524777-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.524797-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.524809-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525000-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525022-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525038-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525055-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525070-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525082-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525240-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525252-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525264-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525275-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525285-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525296-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525571-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525586-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525597-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525608-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525618-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525629-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525772-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525784-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525794-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525805-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525816-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.525825-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526018-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526030-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526041-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526051-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526062-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526072-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526205-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526217-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526228-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526238-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526248-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526259-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526349-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526361-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526375-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526386-0700 Atoll[56405:6258887] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=242257630330881, rateLimit=32hz }
2026-10-06 21:02:43.526444-0700 Atoll[56405:6258887] [carc] Reporter disconnected or already stopped. { func=stop, reporterID=242257630330881 }
2026-10-06 21:02:43.573758-0700 Atoll[56405:6258887] [] CMIO_DAL_CMIOExtension_Device.mm:373:Device legacy uuid isn't present, using new style uuid instead
2026-10-06 21:02:43.710946-0700 Atoll[56405:6258903] [] warning: failed to mark memory(GRAPHICS) error 0x8 ((os/kern) no access)

Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.

Test Suite 'Selected tests' started at 2026-10-06 21:02:43.786.
Test Suite 'DynamicIslandTests.xctest' started at 2026-10-06 21:02:43.787.
Test Suite 'NextVersionReliabilityTests' started at 2026-10-06 21:02:43.787.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testPermissionSnapshotRequiresReadAccessAndDistinguishesCameraDenial]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testPermissionSnapshotRequiresReadAccessAndDistinguishesCameraDenial]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testReadOnlyFindBarOpensAndCancelsWithoutEditingOrChangingUndo]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testReadOnlyFindBarOpensAndCancelsWithoutEditingOrChangingUndo]' passed (0.202 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testReduceMotionRemovesTheActualCoreAnimationPulse]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testReduceMotionRemovesTheActualCoreAnimationPulse]' passed (0.030 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testReminderSnapshotFollowsTodayAndRollsAcrossMidnightIndependentlyOfHome]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testReminderSnapshotFollowsTodayAndRollsAcrossMidnightIndependentlyOfHome]' passed (0.007 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testRoutingUsesSavedOrderAndKeepsColorPickerSeparate]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testRoutingUsesSavedOrderAndKeepsColorPickerSeparate]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testShelfDisableRetainsContentAcrossPersistenceAndExplicitClear]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testShelfDisableRetainsContentAcrossPersistenceAndExplicitClear]' passed (0.044 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testTextExportPreservesUnicodeAndFailureDoesNotChangeTheDocument]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testTextExportPreservesUnicodeAndFailureDoesNotChangeTheDocument]' passed (0.003 seconds).
Test Suite 'NextVersionReliabilityTests' passed at 2026-10-06 21:02:44.077.
	 Executed 7 tests, with 0 failures (0 unexpected) in 0.288 (0.290) seconds
Test Suite 'ShelfTests' started at 2026-10-06 21:02:44.077.
Test Case '-[DynamicIslandTests.ShelfTests testActiveLeaseSurvivesClearAndReleasesExactlyOnce]' started.
Test Case '-[DynamicIslandTests.ShelfTests testActiveLeaseSurvivesClearAndReleasesExactlyOnce]' passed (0.005 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testANameThatWouldMoveTheFileIsRefused]' started.
Test Case '-[DynamicIslandTests.ShelfTests testANameThatWouldMoveTheFileIsRefused]' passed (0.002 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testAnEmptyListFoundAtLaunchIsRemoved]' started.
Test Case '-[DynamicIslandTests.ShelfTests testAnEmptyListFoundAtLaunchIsRemoved]' passed (0.002 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testAnEmptyNameIsRefused]' started.
Test Case '-[DynamicIslandTests.ShelfTests testAnEmptyNameIsRefused]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testARenameStaysInTheFilesFolder]' started.
Test Case '-[DynamicIslandTests.ShelfTests testARenameStaysInTheFilesFolder]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testCancelledProviderDoesNotLeaveAWaitingTask]' started.
Test Case '-[DynamicIslandTests.ShelfTests testCancelledProviderDoesNotLeaveAWaitingTask]' passed (0.002 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testCancelledShareBalancesInteractionOnce]' started.
Test Case '-[DynamicIslandTests.ShelfTests testCancelledShareBalancesInteractionOnce]' passed (0.003 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testClipboardOwnershipReplacementReleasesFilesWithoutPolling]' started.
Test Case '-[DynamicIslandTests.ShelfTests testClipboardOwnershipReplacementReleasesFilesWithoutPolling]' passed (0.107 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testCorruptHandoffLedgerDisablesDestructiveCleanup]' started.
Test Case '-[DynamicIslandTests.ShelfTests testCorruptHandoffLedgerDisablesDestructiveCleanup]' passed (0.007 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testCorruptStoreIsPreservedAndNeverTreatedAsEmpty]' started.
Test Case '-[DynamicIslandTests.ShelfTests testCorruptStoreIsPreservedAndNeverTreatedAsEmpty]' passed (0.003 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testEmptyingTheShelfLeavesNothingOnDisk]' started.
Test Case '-[DynamicIslandTests.ShelfTests testEmptyingTheShelfLeavesNothingOnDisk]' passed (0.002 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testEmptyingTheShelfSparesOtherFilesInItsFolder]' started.
Test Case '-[DynamicIslandTests.ShelfTests testEmptyingTheShelfSparesOtherFilesInItsFolder]' passed (0.002 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testHandoffSurvivesRelaunchAndExpiresPerFile]' started.
Test Case '-[DynamicIslandTests.ShelfTests testHandoffSurvivesRelaunchAndExpiresPerFile]' passed (0.006 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testOtherHandoffsDoNotExtendAnEarlierFilesExpiry]' started.
Test Case '-[DynamicIslandTests.ShelfTests testOtherHandoffsDoNotExtendAnEarlierFilesExpiry]' passed (0.004 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testOwnershipRejectsPrefixCollisionsAndEscapingSymlinks]' started.
Test Case '-[DynamicIslandTests.ShelfTests testOwnershipRejectsPrefixCollisionsAndEscapingSymlinks]' passed (0.002 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testPreviewKeepsOrdinaryURLsAndReleasesOnHide]' started.
Test Case '-[DynamicIslandTests.ShelfTests testPreviewKeepsOrdinaryURLsAndReleasesOnHide]' passed (0.046 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testProviderFilenameCannotEscapeDestination]' started.
Test Case '-[DynamicIslandTests.ShelfTests testProviderFilenameCannotEscapeDestination]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testRepeatedUseLeavesNoActiveLeaseOrIdleWake]' started.
Test Case '-[DynamicIslandTests.ShelfTests testRepeatedUseLeavesNoActiveLeaseOrIdleWake]' passed (0.071 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testSavedItemsComeBack]' started.
Test Case '-[DynamicIslandTests.ShelfTests testSavedItemsComeBack]' passed (0.002 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testSaveFailureIsObservable]' started.
Test Case '-[DynamicIslandTests.ShelfTests testSaveFailureIsObservable]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testShareWaitsForCompletionInsteadOfTwoSecondTimeout]' started.
Test Case '-[DynamicIslandTests.ShelfTests testShareWaitsForCompletionInsteadOfTwoSecondTimeout]' passed (2.424 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testTextAndLinkMetadataAppearImmediatelyAndUpdate]' started.
Test Case '-[DynamicIslandTests.ShelfTests testTextAndLinkMetadataAppearImmediatelyAndUpdate]' passed (0.006 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testTheSameNameIsNotARename]' started.
Test Case '-[DynamicIslandTests.ShelfTests testTheSameNameIsNotARename]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testTheSweepKeepsFilesInUseAndFilesJustMade]' started.
Test Case '-[DynamicIslandTests.ShelfTests testTheSweepKeepsFilesInUseAndFilesJustMade]' passed (0.004 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testThumbnailCacheStaysWithinEntryAndPixelBudgets]' started.
Shelf cache verification: generated=60, entries=48, accountedBytes=2408448
Test Case '-[DynamicIslandTests.ShelfTests testThumbnailCacheStaysWithinEntryAndPixelBudgets]' passed (0.877 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testThumbnailWorkIsBoundedAndCancellationEmptiesQueue]' started.
2026-10-06 21:02:47.673754-0700 Atoll[56405:6258903] [cloudthumbnails.client] getattrlist() failed for file:///var/folders/bj/_6886nzd0rd2f4vvw_2bdq7h0000gn/T/ShelfTests-34061D55-9265-4118-97FB-36BC05423DE3/missing-1.png: 2 (No such file or directory)
2026-10-06 21:02:47.675487-0700 Atoll[56405:6258903] [cloudthumbnails.client] getattrlist() failed for file:///var/folders/bj/_6886nzd0rd2f4vvw_2bdq7h0000gn/T/ShelfTests-34061D55-9265-4118-97FB-36BC05423DE3/missing-0.png: 2 (No such file or directory)
2026-10-06 21:02:47.678506-0700 Atoll[56405:6258903] [cloudthumbnails.client] getattrlist() failed for file:///var/folders/bj/_6886nzd0rd2f4vvw_2bdq7h0000gn/T/ShelfTests-34061D55-9265-4118-97FB-36BC05423DE3/missing-24.png: 2 (No such file or directory)
Test Case '-[DynamicIslandTests.ShelfTests testThumbnailWorkIsBoundedAndCancellationEmptiesQueue]' passed (0.012 seconds).
Test Suite 'ShelfTests' passed at 2026-10-06 21:02:47.683.
	 Executed 26 tests, with 0 failures (0 unexpected) in 3.597 (3.605) seconds
Test Suite 'DynamicIslandTests.xctest' passed at 2026-10-06 21:02:47.683.
	 Executed 33 tests, with 0 failures (0 unexpected) in 3.884 (3.896) seconds
Test Suite 'Selected tests' passed at 2026-10-06 21:02:47.683.
	 Executed 33 tests, with 0 failures (0 unexpected) in 3.884 (3.897) seconds
2026-10-06 21:02:57.445 xcodebuild[56276:6257758] [MT] IDETestOperationsObserverDebug: 27.122 elapsed -- Testing started completed.
2026-10-06 21:02:57.446 xcodebuild[56276:6257758] [MT] IDETestOperationsObserverDebug: 0.000 sec, +0.000 sec -- start
2026-10-06 21:02:57.446 xcodebuild[56276:6257758] [MT] IDETestOperationsObserverDebug: 27.122 sec, +27.122 sec -- end

Test session results, code coverage, and logs:
	/tmp/atoll-next-version-fixes/native-final-results.xcresult

Failing tests:
	NextVersionReliabilityTests.testCoordinatorRoutesDisabledCurrentRememberedAndShortcutTargets()

** TEST EXECUTE FAILED **

Testing started

```
