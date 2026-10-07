```text
DynamicIsland/managers/Agents/AgentEventServer.swift:266:59: warning: capture of 'self' with non-Sendable type 'AgentEventServer' in a '@Sendable' closure [#SendableClosureCaptures]
    |                                                           `- warning: capture of 'self' with non-Sendable type 'AgentEventServer' in a '@Sendable' closure [#SendableClosureCaptures]
DynamicIsland/managers/Agents/ProcessRunner.swift:96:59: warning: 'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope [#ImplicitStrongCapture]
    |                                                           |- warning: 'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope [#ImplicitStrongCapture]
DynamicIsland/managers/Agents/ProcessRunner.swift:105:61: warning: 'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope [#ImplicitStrongCapture]
    |                                                             |- warning: 'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope [#ImplicitStrongCapture]
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/usr/include/sys/sysctl.h:808:9: warning: could not load macro '_SwiftifyImport'; this may cause errors down the line
    |         `- warning: could not load macro '_SwiftifyImport'; this may cause errors down the line
```
