Before retaining the emitted policy, the actual sampler failed to start. The final native suite includes the passing regression.

```text
/Users/yichenlin/Desktop/Tester/Atoll/DynamicIslandTests/LightweightPolicyTests.swift:129: error: -[DynamicIslandTests.LightweightPolicyTests testStatsStartsFromPublishedVisibilityAndStopsWhenHidden] : XCTAssertTrue failed - The subscriber must use the published policy, not the monitor's old willSet value.
	 Executed 1 test, with 1 failure (0 unexpected) in 0.313 (0.314) seconds
	 Executed 1 test, with 1 failure (0 unexpected) in 0.313 (0.315) seconds
	 Executed 1 test, with 1 failure (0 unexpected) in 0.313 (0.316) seconds
** TEST FAILED **
```
