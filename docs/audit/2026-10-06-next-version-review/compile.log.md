# Isolated Agent probe compile log

Exit status: 0. SDK macro/implicit-capture warnings were emitted; the binary compiled and the replay completed.

```text
DynamicIsland/managers/Agents/AgentEventServer.swift:266:59: warning: capture of 'self' with non-Sendable type 'AgentEventServer' in a '@Sendable' closure [#SendableClosureCaptures]
 10 | /// A request stays open until it is answered, which lets a hook wait for a
 11 | /// message typed in Atoll.
 12 | final class AgentEventServer {
    |             `- note: class 'AgentEventServer' does not conform to the 'Sendable' protocol
 13 |     struct Request {
 14 |         let path: String
    :
264 |     func resourceCounts() async -> (connections: Int, bufferedBytes: Int, waiting: Int) {
265 |         await withCheckedContinuation { continuation in
266 |             queue.async { continuation.resume(returning: (self.incoming.count, self.bufferedBytes, self.waiting.count)) }
    |                                                           `- warning: capture of 'self' with non-Sendable type 'AgentEventServer' in a '@Sendable' closure [#SendableClosureCaptures]
267 |         }
268 |     }

[#SendableClosureCaptures]: <https://docs.swift.org/compiler/documentation/diagnostics/sendable-closure-captures>
DynamicIsland/managers/Agents/ProcessRunner.swift:96:59: warning: 'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope [#ImplicitStrongCapture]
 91 |
 92 |         func start(_ continuation: CheckedContinuation<Outcome, Error>, timeout: TimeInterval?) {
 93 |             queue.async {
    |                         |- note: 'self' implicitly strongly captured here
    |                         `- note: add 'self' as a capture list item to silence
 94 |                 guard !self.cancelled else { continuation.resume(throwing: CancellationError()); return }
 95 |                 self.continuation = continuation
 96 |                 self.process.terminationHandler = { [weak self] process in
    |                                                           |- warning: 'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope [#ImplicitStrongCapture]
    |                                                           `- note: explicitly assign the capture list item to silence
 97 |                     let status = process.terminationStatus
 98 |                     guard let self else { return }

DynamicIsland/managers/Agents/ProcessRunner.swift:105:61: warning: 'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope [#ImplicitStrongCapture]
 91 |
 92 |         func start(_ continuation: CheckedContinuation<Outcome, Error>, timeout: TimeInterval?) {
 93 |             queue.async {
    |                         |- note: 'self' implicitly strongly captured here
    |                         `- note: add 'self' as a capture list item to silence
 94 |                 guard !self.cancelled else { continuation.resume(throwing: CancellationError()); return }
 95 |                 self.continuation = continuation
    :
103 |                     self.childPID = self.process.processIdentifier
104 |                     if let timeout {
105 |                         let work = DispatchWorkItem { [weak self] in
    |                                                             |- warning: 'weak' ownership of capture 'self' differs from implicitly-captured strong reference in outer scope [#ImplicitStrongCapture]
    |                                                             `- note: explicitly assign the capture list item to silence
106 |                             guard let self, self.continuation != nil, self.process.isRunning else { return }
107 |                             self.timedOut = true

[#ImplicitStrongCapture]: <https://docs.swift.org/compiler/documentation/diagnostics/implicit-strong-capture>
sandbox-exec: sandbox_apply: Operation not permitted
/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/usr/include/sys/sysctl.h:808:9: warning: could not load macro '_SwiftifyImport'; this may cause errors down the line
806 |
807 | __BEGIN_DECLS
808 | int     sysctl(int *, u_int, void *__sized_by(*oldlenp), size_t *oldlenp,
    |         `- warning: could not load macro '_SwiftifyImport'; this may cause errors down the line
809 |     void *__sized_by(newlen), size_t newlen);
810 | int     sysctlbyname(const char *, void *__sized_by(*oldlenp), size_t *oldlenp,

```
