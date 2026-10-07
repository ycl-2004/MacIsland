A deterministic microtask replay failed before the drain was restarted/adopted in finally. The current queue acceptance includes this passing fixture.

```text
node:internal/modules/run_main:107
    triggerUncaughtException(
    ^

AssertionError [ERR_ASSERTION]: An event queued between drain completion and finally must restart draining.
    at file:///Users/yichenlin/Desktop/Tester/Atoll/tests/AgentPluginQueueAudit.mjs:59:1 {
  generatedMessage: false,
  code: 'ERR_ASSERTION',
  actual: false,
  expected: true,
  operator: '==',
  diff: 'simple'
}

Node.js v26.9.0

```
