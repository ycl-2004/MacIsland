# Native regression — 68 tests

```text
Command line invocation:
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test-without-building -xctestrun /tmp/atoll-next-version-fixes/native-verified/DynamicIsland.xctestrun -destination platform=macOS -resultBundlePath /tmp/atoll-next-version-fixes/native-verified-results.xcresult

Writing result bundle at path:
	/tmp/atoll-next-version-fixes/native-verified-results.xcresult

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
2026-10-06 21:06:21.427895-0700 Atoll[57514:6267782] ✅ Fullscreen status: ["Built-in Retina Display": false]
2026-10-06 21:06:21.489282-0700 Atoll[57514:6267782] [plugin] AddInstanceForFactory: No factory registered for id <CFUUID 0x7c608cdf40> F8BB1C28-BAE8-11D6-9C31-00039315CD46
2026-10-06 21:06:23.349264-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349333-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349365-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349393-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349421-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349447-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349476-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349506-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349631-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349660-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349683-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349703-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349725-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349769-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349828-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349852-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349871-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349887-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349903-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349922-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.349991-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350008-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350024-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350041-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350059-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350075-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350107-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350125-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350140-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350156-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350173-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350188-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350227-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350243-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350258-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350273-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350290-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350306-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350345-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350362-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350378-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350397-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350414-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350430-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350445-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350459-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350474-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350488-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350504-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350521-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350561-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350577-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350593-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350609-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350625-0700 Atoll[57514:6267782] [carc] Message send exceeds rate-limit threshold and will be dropped. { reporterID=247020749062145, rateLimit=32hz }
2026-10-06 21:06:23.350694-0700 Atoll[57514:6267782] [carc] Reporter disconnected or already stopped. { func=stop, reporterID=247020749062145 }
2026-10-06 21:06:23.440143-0700 Atoll[57514:6267782] [] CMIO_DAL_CMIOExtension_Device.mm:373:Device legacy uuid isn't present, using new style uuid instead
2026-10-06 21:06:23.749233-0700 Atoll[57514:6267883] [] warning: failed to mark memory(GRAPHICS) error 0x8 ((os/kern) no access)
2026-10-06 21:06:23.771359-0700 Atoll[57514:6267883] fopen failed for data file: errno = 2 (No such file or directory)
2026-10-06 21:06:24.164889-0700 Atoll[57514:6268187] fopen failed for data file: errno = 2 (No such file or directory)
Test Suite 'Selected tests' started at 2026-10-06 21:06:24.201.
Test Suite 'DynamicIslandTests.xctest' started at 2026-10-06 21:06:24.202.
Test Suite 'ContentReliabilityTests' started at 2026-10-06 21:06:24.202.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testAgentMemoryKeepsOnlyRecentBoundedCards]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testAgentMemoryKeepsOnlyRecentBoundedCards]' passed (0.025 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testAgentSnapshotBudgetReloadsLargeMultiSessionHistory]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testAgentSnapshotBudgetReloadsLargeMultiSessionHistory]' passed (0.188 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testExplicitRecoveryKeepsTheCurrentVersion]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testExplicitRecoveryKeepsTheCurrentVersion]' passed (0.078 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testExtraSpaceRejectsOversizedChangesWithoutReplacingContent]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testExtraSpaceRejectsOversizedChangesWithoutReplacingContent]' passed (0.093 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testFailedTimerSoundImportLeavesPreviousSound]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testFailedTimerSoundImportLeavesPreviousSound]' passed (0.004 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testOversizedExtraSpaceFileIsKeptAndNotLoadedOrOverwritten]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testOversizedExtraSpaceFileIsKeptAndNotLoadedOrOverwritten]' passed (0.017 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testRecoveryWritesEvenWhenThePreviousTextMatchesTheCurrentDraft]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testRecoveryWritesEvenWhenThePreviousTextMatchesTheCurrentDraft]' passed (0.057 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testRepeatedSaveKeepsPreviousVersionAndPrivatePermissions]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testRepeatedSaveKeepsPreviousVersionAndPrivatePermissions]' passed (0.016 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testSharedContentUsesIsolatedTestPaths]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testSharedContentUsesIsolatedTestPaths]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testShelfOwnedCopyHasAByteBudgetAndPrivatePermissions]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testShelfOwnedCopyHasAByteBudgetAndPrivatePermissions]' passed (0.003 seconds).
Test Case '-[DynamicIslandTests.ContentReliabilityTests testZipSnapshotsInputsAndPreservesSingleFileName]' started.
Test Case '-[DynamicIslandTests.ContentReliabilityTests testZipSnapshotsInputsAndPreservesSingleFileName]' passed (0.016 seconds).
Test Suite 'ContentReliabilityTests' passed at 2026-10-06 21:06:24.703.
	 Executed 11 tests, with 0 failures (0 unexpected) in 0.497 (0.501) seconds
Test Suite 'ExtraSpaceTests' started at 2026-10-06 21:06:24.703.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testAutosaveCoalescesEditsAndImmediateSaveKeepsTheNewestText]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testAutosaveCoalescesEditsAndImmediateSaveKeepsTheNewestText]' passed (0.293 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testDoubleClickAndCommandSSwitchTheRealTabBetweenEditingAndReading]' started.
2026-10-06 21:06:25.298714-0700 Atoll[57514:6268205] [Common] Unable to obtain a task name port right for pid 413: (os/kern) failure (0x5)
2026-10-06 21:06:25.454312-0700 Atoll[57514:6267782] [CursorUI] ViewBridge to RemoteViewService Terminated: Error Domain=com.apple.ViewBridge.error Code=18 "(null)" UserInfo={com.apple.ViewBridge.error.hint=this process disconnected remote view controller -- benign unless unexpected, com.apple.ViewBridge.error.description=NSViewBridgeErrorCanceled}
Test Case '-[DynamicIslandTests.ExtraSpaceTests testDoubleClickAndCommandSSwitchTheRealTabBetweenEditingAndReading]' passed (0.681 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testExtraSpaceUsesTheSameDefaultHeightAsOtherMainTabs]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testExtraSpaceUsesTheSameDefaultHeightAsOtherMainTabs]' passed (0.002 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testKeyboardUndoReachesTheFocusedNativeEditor]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testKeyboardUndoReachesTheFocusedNativeEditor]' passed (0.372 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testLongNativeEditorRestoresSelectionAndScrollPositionAfterRemount]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testLongNativeEditorRestoresSelectionAndScrollPositionAfterRemount]' passed (0.273 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testNativeTypingCompositionAndUndoUpdateTheSameDocument]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testNativeTypingCompositionAndUndoUpdateTheSameDocument]' passed (0.115 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testSaveEndsEditingAndReadingSwipeClosesWithoutScrollingOrEditing]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testSaveEndsEditingAndReadingSwipeClosesWithoutScrollingOrEditing]' passed (0.132 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testSaveFailureRetainsTheDraftAndCanBeRetried]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testSaveFailureRetainsTheDraftAndCanBeRetried]' passed (0.026 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testTabAndSettingsRenderWithTheExistingVisualSystem]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testTabAndSettingsRenderWithTheExistingVisualSystem]' passed (0.456 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testTerminationFlushAndReopeningPreserveUnicodeAndNewlines]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testTerminationFlushAndReopeningPreserveUnicodeAndNewlines]' passed (0.027 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testToolbarPasteIsOneUndoableEdit]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testToolbarPasteIsOneUndoableEdit]' passed (0.111 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testTwoEditorsShareTextWithoutKeepingInvalidUndoRanges]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testTwoEditorsShareTextWithoutKeepingInvalidUndoRanges]' passed (0.101 seconds).
Test Case '-[DynamicIslandTests.ExtraSpaceTests testUnreadableDocumentCannotBeOverwrittenByAnEmptyEditor]' started.
Test Case '-[DynamicIslandTests.ExtraSpaceTests testUnreadableDocumentCannotBeOverwrittenByAnEmptyEditor]' passed (0.026 seconds).
Test Suite 'ExtraSpaceTests' passed at 2026-10-06 21:06:27.323.
	 Executed 13 tests, with 0 failures (0 unexpected) in 2.615 (2.619) seconds
Test Suite 'LightweightPolicyTests' started at 2026-10-06 21:06:27.323.
Test Case '-[DynamicIslandTests.LightweightPolicyTests testBackgroundStatsResumeAfterUnlockButDoNotColdStart]' started.
2026-10-06 21:06:27.462623-0700 Atoll[57514:6267782] [debug] 🔍 [2026-10-07T04:06:27.462Z] [StatsManager.swift:191] startMonitoring() - StatsManager: Starting monitoring...
🔍 [2026-10-07T04:06:27.462Z] [StatsManager.swift:191] startMonitoring() - StatsManager: Starting monitoring...
2026-10-06 21:06:27.466324-0700 Atoll[57514:6267782] [debug] 🔍 [2026-10-07T04:06:27.466Z] [StatsManager.swift:214] startMonitoring() - StatsManager: Monitoring started
🔍 [2026-10-07T04:06:27.466Z] [StatsManager.swift:214] startMonitoring() - StatsManager: Monitoring started
2026-10-06 21:06:27.466393-0700 Atoll[57514:6267782] [debug] 🔍 [2026-10-07T04:06:27.466Z] [StatsManager.swift:227] stopMonitoring() - StatsManager: Monitoring stopped
🔍 [2026-10-07T04:06:27.466Z] [StatsManager.swift:227] stopMonitoring() - StatsManager: Monitoring stopped
2026-10-06 21:06:27.466650-0700 Atoll[57514:6267782] [debug] 🔍 [2026-10-07T04:06:27.467Z] [StatsManager.swift:191] startMonitoring() - StatsManager: Starting monitoring...
🔍 [2026-10-07T04:06:27.467Z] [StatsManager.swift:191] startMonitoring() - StatsManager: Starting monitoring...
2026-10-06 21:06:27.469819-0700 Atoll[57514:6267782] [debug] 🔍 [2026-10-07T04:06:27.470Z] [StatsManager.swift:214] startMonitoring() - StatsManager: Monitoring started
🔍 [2026-10-07T04:06:27.470Z] [StatsManager.swift:214] startMonitoring() - StatsManager: Monitoring started
2026-10-06 21:06:27.470565-0700 Atoll[57514:6267782] [debug] 🔍 [2026-10-07T04:06:27.471Z] [StatsManager.swift:227] stopMonitoring() - StatsManager: Monitoring stopped
🔍 [2026-10-07T04:06:27.471Z] [StatsManager.swift:227] stopMonitoring() - StatsManager: Monitoring stopped
Test Case '-[DynamicIslandTests.LightweightPolicyTests testBackgroundStatsResumeAfterUnlockButDoNotColdStart]' passed (0.148 seconds).
Test Case '-[DynamicIslandTests.LightweightPolicyTests testConnectionRefreshSlowsWithoutDisablingEvents]' started.
Test Case '-[DynamicIslandTests.LightweightPolicyTests testConnectionRefreshSlowsWithoutDisablingEvents]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.LightweightPolicyTests testFeatureManagementDestinationRendersInTheSettingsWindow]' started.
Test Case '-[DynamicIslandTests.LightweightPolicyTests testFeatureManagementDestinationRendersInTheSettingsWindow]' passed (0.869 seconds).
Test Case '-[DynamicIslandTests.LightweightPolicyTests testPresetRoundTripAndShelfExclusion]' started.
Test Case '-[DynamicIslandTests.LightweightPolicyTests testPresetRoundTripAndShelfExclusion]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.LightweightPolicyTests testPresetUndoProtectsManualEditsIncludingRoundTrips]' started.
Test Case '-[DynamicIslandTests.LightweightPolicyTests testPresetUndoProtectsManualEditsIncludingRoundTrips]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.LightweightPolicyTests testRealDefaultsTransactionRejectsStalePreviewAndPreservesLaterEdits]' started.
Test Case '-[DynamicIslandTests.LightweightPolicyTests testRealDefaultsTransactionRejectsStalePreviewAndPreservesLaterEdits]' passed (0.008 seconds).
Test Case '-[DynamicIslandTests.LightweightPolicyTests testStatsGateAndBackgroundCadence]' started.
Test Case '-[DynamicIslandTests.LightweightPolicyTests testStatsGateAndBackgroundCadence]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.LightweightPolicyTests testStatsStartsFromPublishedVisibilityAndStopsWhenHidden]' started.
2026-10-06 21:06:28.356169-0700 Atoll[57514:6267782] [debug] 🔍 [2026-10-07T04:06:28.356Z] [StatsManager.swift:191] startMonitoring() - StatsManager: Starting monitoring...
🔍 [2026-10-07T04:06:28.356Z] [StatsManager.swift:191] startMonitoring() - StatsManager: Starting monitoring...
2026-10-06 21:06:28.359544-0700 Atoll[57514:6267782] [debug] 🔍 [2026-10-07T04:06:28.360Z] [StatsManager.swift:214] startMonitoring() - StatsManager: Monitoring started
🔍 [2026-10-07T04:06:28.360Z] [StatsManager.swift:214] startMonitoring() - StatsManager: Monitoring started
2026-10-06 21:06:28.359602-0700 Atoll[57514:6267782] [debug] 🔍 [2026-10-07T04:06:28.360Z] [StatsManager.swift:227] stopMonitoring() - StatsManager: Monitoring stopped
🔍 [2026-10-07T04:06:28.360Z] [StatsManager.swift:227] stopMonitoring() - StatsManager: Monitoring stopped
Test Case '-[DynamicIslandTests.LightweightPolicyTests testStatsStartsFromPublishedVisibilityAndStopsWhenHidden]' passed (0.006 seconds).
Test Suite 'LightweightPolicyTests' passed at 2026-10-06 21:06:28.361.
	 Executed 8 tests, with 0 failures (0 unexpected) in 1.035 (1.038) seconds
Test Suite 'NextVersionReliabilityTests' started at 2026-10-06 21:06:28.361.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testCalendarServiceOnlyQueriesForDemandAndPreservesReminderConsumer]' started.
2026-10-06 21:06:28.376392-0700 Atoll[57514:6267782] [lifecycle] 🔄 [2026-10-07T04:06:28.376Z] [CalendarManager.swift:449] updateEvents(force:) - CalendarManager: Updating events (force: false)
🔄 [2026-10-07T04:06:28.376Z] [CalendarManager.swift:449] updateEvents(force:) - CalendarManager: Updating events (force: false)
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testCalendarServiceOnlyQueriesForDemandAndPreservesReminderConsumer]' passed (0.197 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testCoordinatorRoutesDisabledCurrentRememberedAndShortcutTargets]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testCoordinatorRoutesDisabledCurrentRememberedAndShortcutTargets]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testPermissionSnapshotRequiresReadAccessAndDistinguishesCameraDenial]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testPermissionSnapshotRequiresReadAccessAndDistinguishesCameraDenial]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testReadOnlyFindBarOpensAndCancelsWithoutEditingOrChangingUndo]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testReadOnlyFindBarOpensAndCancelsWithoutEditingOrChangingUndo]' passed (0.139 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testReduceMotionRemovesTheActualCoreAnimationPulse]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testReduceMotionRemovesTheActualCoreAnimationPulse]' passed (0.027 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testReminderCompletionImmediatelyUpdatesTheIndependentSnapshot]' started.
2026-10-06 21:06:28.734935-0700 Atoll[57514:6267782] [lifecycle] 🔄 [2026-10-07T04:06:28.735Z] [CalendarManager.swift:449] updateEvents(force:) - CalendarManager: Updating events (force: true)
🔄 [2026-10-07T04:06:28.735Z] [CalendarManager.swift:449] updateEvents(force:) - CalendarManager: Updating events (force: true)
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testReminderCompletionImmediatelyUpdatesTheIndependentSnapshot]' passed (0.008 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testReminderSnapshotFollowsTodayAndRollsAcrossMidnightIndependentlyOfHome]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testReminderSnapshotFollowsTodayAndRollsAcrossMidnightIndependentlyOfHome]' passed (0.007 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testRoutingUsesSavedOrderAndKeepsColorPickerSeparate]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testRoutingUsesSavedOrderAndKeepsColorPickerSeparate]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testShelfDisableRetainsContentAcrossPersistenceAndExplicitClear]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testShelfDisableRetainsContentAcrossPersistenceAndExplicitClear]' passed (0.046 seconds).
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testTextExportPreservesUnicodeAndFailureDoesNotChangeTheDocument]' started.
Test Case '-[DynamicIslandTests.NextVersionReliabilityTests testTextExportPreservesUnicodeAndFailureDoesNotChangeTheDocument]' passed (0.002 seconds).
Test Suite 'NextVersionReliabilityTests' passed at 2026-10-06 21:06:28.793.
	 Executed 10 tests, with 0 failures (0 unexpected) in 0.429 (0.432) seconds
Test Suite 'ShelfTests' started at 2026-10-06 21:06:28.794.
Test Case '-[DynamicIslandTests.ShelfTests testActiveLeaseSurvivesClearAndReleasesExactlyOnce]' started.
Test Case '-[DynamicIslandTests.ShelfTests testActiveLeaseSurvivesClearAndReleasesExactlyOnce]' passed (0.004 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testANameThatWouldMoveTheFileIsRefused]' started.
Test Case '-[DynamicIslandTests.ShelfTests testANameThatWouldMoveTheFileIsRefused]' passed (0.001 seconds).
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
Test Case '-[DynamicIslandTests.ShelfTests testClipboardOwnershipReplacementReleasesFilesWithoutPolling]' passed (0.146 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testCorruptHandoffLedgerDisablesDestructiveCleanup]' started.
Test Case '-[DynamicIslandTests.ShelfTests testCorruptHandoffLedgerDisablesDestructiveCleanup]' passed (0.003 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testCorruptStoreIsPreservedAndNeverTreatedAsEmpty]' started.
Test Case '-[DynamicIslandTests.ShelfTests testCorruptStoreIsPreservedAndNeverTreatedAsEmpty]' passed (0.004 seconds).
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
Test Case '-[DynamicIslandTests.ShelfTests testPreviewKeepsOrdinaryURLsAndReleasesOnHide]' passed (0.030 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testProviderFilenameCannotEscapeDestination]' started.
Test Case '-[DynamicIslandTests.ShelfTests testProviderFilenameCannotEscapeDestination]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testRepeatedUseLeavesNoActiveLeaseOrIdleWake]' started.
Test Case '-[DynamicIslandTests.ShelfTests testRepeatedUseLeavesNoActiveLeaseOrIdleWake]' passed (0.077 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testSavedItemsComeBack]' started.
Test Case '-[DynamicIslandTests.ShelfTests testSavedItemsComeBack]' passed (0.002 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testSaveFailureIsObservable]' started.
Test Case '-[DynamicIslandTests.ShelfTests testSaveFailureIsObservable]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testShareWaitsForCompletionInsteadOfTwoSecondTimeout]' started.
Test Case '-[DynamicIslandTests.ShelfTests testShareWaitsForCompletionInsteadOfTwoSecondTimeout]' passed (2.244 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testTextAndLinkMetadataAppearImmediatelyAndUpdate]' started.
Test Case '-[DynamicIslandTests.ShelfTests testTextAndLinkMetadataAppearImmediatelyAndUpdate]' passed (0.005 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testTheSameNameIsNotARename]' started.
Test Case '-[DynamicIslandTests.ShelfTests testTheSameNameIsNotARename]' passed (0.001 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testTheSweepKeepsFilesInUseAndFilesJustMade]' started.
Test Case '-[DynamicIslandTests.ShelfTests testTheSweepKeepsFilesInUseAndFilesJustMade]' passed (0.003 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testThumbnailCacheStaysWithinEntryAndPixelBudgets]' started.
Shelf cache verification: generated=60, entries=48, accountedBytes=2408448
Test Case '-[DynamicIslandTests.ShelfTests testThumbnailCacheStaysWithinEntryAndPixelBudgets]' passed (1.113 seconds).
Test Case '-[DynamicIslandTests.ShelfTests testThumbnailWorkIsBoundedAndCancellationEmptiesQueue]' started.
2026-10-06 21:06:32.466150-0700 Atoll[57514:6268205] [cloudthumbnails.client] getattrlist() failed for file:///var/folders/bj/_6886nzd0rd2f4vvw_2bdq7h0000gn/T/ShelfTests-8AC161D1-5621-42F2-A707-52DB93C9DE17/missing-0.png: 2 (No such file or directory)
2026-10-06 21:06:32.467766-0700 Atoll[57514:6268205] [cloudthumbnails.client] getattrlist() failed for file:///var/folders/bj/_6886nzd0rd2f4vvw_2bdq7h0000gn/T/ShelfTests-8AC161D1-5621-42F2-A707-52DB93C9DE17/missing-1.png: 2 (No such file or directory)
2026-10-06 21:06:32.469859-0700 Atoll[57514:6268205] [cloudthumbnails.client] getattrlist() failed for file:///var/folders/bj/_6886nzd0rd2f4vvw_2bdq7h0000gn/T/ShelfTests-8AC161D1-5621-42F2-A707-52DB93C9DE17/missing-18.png: 2 (No such file or directory)
2026-10-06 21:06:32.473171-0700 Atoll[57514:6268205] [cloudthumbnails.client] getattrlist() failed for file:///var/folders/bj/_6886nzd0rd2f4vvw_2bdq7h0000gn/T/ShelfTests-8AC161D1-5621-42F2-A707-52DB93C9DE17/missing-46.png: 2 (No such file or directory)
2026-10-06 21:06:32.475822-0700 Atoll[57514:6268205] [cloudthumbnails.client] getattrlist() failed for file:///var/folders/bj/_6886nzd0rd2f4vvw_2bdq7h0000gn/T/ShelfTests-8AC161D1-5621-42F2-A707-52DB93C9DE17/missing-73.png: 2 (No such file or directory)
Test Case '-[DynamicIslandTests.ShelfTests testThumbnailWorkIsBoundedAndCancellationEmptiesQueue]' passed (0.013 seconds).
Test Suite 'ShelfTests' passed at 2026-10-06 21:06:32.476.
	 Executed 26 tests, with 0 failures (0 unexpected) in 3.675 (3.683) seconds
Test Suite 'DynamicIslandTests.xctest' passed at 2026-10-06 21:06:32.477.
	 Executed 68 tests, with 0 failures (0 unexpected) in 8.251 (8.275) seconds
Test Suite 'Selected tests' passed at 2026-10-06 21:06:32.477.
	 Executed 68 tests, with 0 failures (0 unexpected) in 8.251 (8.276) seconds
2026-10-06 21:06:32.769 xcodebuild[57501:6267533] [MT] IDETestOperationsObserverDebug: 13.005 elapsed -- Testing started completed.
2026-10-06 21:06:32.769 xcodebuild[57501:6267533] [MT] IDETestOperationsObserverDebug: 0.000 sec, +0.000 sec -- start
2026-10-06 21:06:32.769 xcodebuild[57501:6267533] [MT] IDETestOperationsObserverDebug: 13.005 sec, +13.005 sec -- end

Test session results, code coverage, and logs:
	/tmp/atoll-next-version-fixes/native-verified-results.xcresult

** TEST EXECUTE SUCCEEDED **

Testing started

```
