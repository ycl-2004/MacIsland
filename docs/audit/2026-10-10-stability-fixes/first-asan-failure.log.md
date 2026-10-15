# First ASAN run — retained failure

Original raw receipt: `/tmp/atoll-stability-fixes/asan-1/native.xcresult` and `native.log`.
The runner at this point did not extract a summary after a native failure; it now always does.

```text
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIslandTests/ExtraSpaceTests.swift:168: error: -[DynamicIslandTests.ExtraSpaceTests testDoubleClickAndCommandSSwitchTheRealTabBetweenEditingAndReading] : XCTUnwrap failed: expected non-nil value of type "ExtraSpaceScrollView"
	 Executed 325 tests, with 1 failure (0 unexpected) in 30.293 (30.646) seconds
	 Executed 325 tests, with 1 failure (0 unexpected) in 30.293 (30.649) seconds
```

The existing editor test used a fixed 50 ms layout delay. It now waits until the actual `ExtraSpaceScrollView` exists. The next ASAN run passed all 326 tests. No ASAN memory-error report occurred in the failed run.
