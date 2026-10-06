#!/usr/bin/env python3
"""Read-only Atoll resource probes. No production app, agent integration, or user data."""
from pathlib import Path
import argparse
import json
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]

def run(command, **kwargs):
    return subprocess.run(command, check=True, capture_output=True, text=True, timeout=45, **kwargs)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("/tmp/atoll-audit-probes.json"))
    args = parser.parse_args()
    results = {}
    with tempfile.TemporaryDirectory(prefix="atoll-resource-audit-", dir="/tmp") as directory:
        work = Path(directory)
        def swift_probe(name, source, originals=()):
            entry = work / (name + ".swift")
            entry.write_text(source)
            binary = work / name
            run(["swiftc", "-parse-as-library", "-module-cache-path", str(work / "modules"),
                 *[str(ROOT / p) for p in originals], str(entry), "-o", str(binary)])
            output = run([str(binary)])
            return {"stdout": output.stdout.strip(), "stderr": output.stderr.strip()}

        handler_source = (ROOT / "DynamicIsland/MediaControllers/NowPlayingController.swift").read_text()
        handler = handler_source[handler_source.index("actor JSONLinesPipeHandler {"):]
        harness = r'''
import Foundation
import Darwin
struct Logger {
    enum Category { case error, warning }
    static func log(_ text: String, category: Category) {}
}
actor Results {
    var values: [String] = []
    var finished = false
    func append(_ value: String) { values.append(value) }
    func finish() { finished = true }
}
struct Payload: Decodable { let text: String }
'''
        harness += (ROOT / "DynamicIsland/utils/PipeReadWaiter.swift").read_text()
        harness += handler
        harness += r'''
@main struct Probe {
    static func decode(split: Bool) async throws -> [String] {
        let handler = JSONLinesPipeHandler()
        let pipe = await handler.getPipe()
        let results = Results()
        let reader = Task {
            await handler.readJSONLines(as: Payload.self) { await results.append($0.text) }
        }
        try await Task.sleep(for: .milliseconds(100))
        let data = Data("{\"text\":\"你好🐳\"}\n".utf8)
        if split {
            let index = data.firstIndex(where: { $0 >= 128 })! + 1
            try pipe.fileHandleForWriting.write(contentsOf: data.prefix(index))
            try await Task.sleep(for: .milliseconds(150))
            try pipe.fileHandleForWriting.write(contentsOf: data.suffix(from: index))
        } else {
            try pipe.fileHandleForWriting.write(contentsOf: data)
        }
        try await Task.sleep(for: .milliseconds(150))
        try pipe.fileHandleForWriting.close()
        await reader.value
        await handler.close()
        return await results.values
    }
    static func main() async throws {
        print("WHOLE_UTF8=\(try await decode(split: false)); SPLIT_UTF8=\(try await decode(split: true))")
        let handler = JSONLinesPipeHandler()
        let results = Results()
        let reader = Task {
            await handler.readJSONLines(as: Payload.self) { await results.append($0.text) }
            await results.finish()
        }
        try await Task.sleep(for: .milliseconds(100))
        reader.cancel()
        await handler.close()
        try await Task.sleep(for: .milliseconds(200))
        print("CANCEL_AND_CLOSE_COMPLETED=\(await results.finished)")
        // A leaked continuation must not leave the audit probe running.
        fflush(stdout)
        exit(0)
    }
}
'''
        results["json_lines_exact_source"] = swift_probe("json-lines", harness)
        agent_harness = r'''
import Foundation
@main struct Probe {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("data")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for count in [1, 14, 60] {
            let file = root.appendingPathComponent("\(count)/sessions.json")
            let store = AgentSessionStore(persistenceURL: file)
            while !store.isLoaded { try await Task.sleep(for: .milliseconds(10)) }
            for index in 0..<count {
                var session = AgentSession(id: "fixture:\(index)", sourceID: "fixture",
                    cwd: nil, hostBundleID: nil, lastPrompt: nil, lastReply: nil, state: .idle,
                    startedAt: Date(), updatedAt: Date(), finishedAt: nil)
                for message in 0..<AgentSession.messageLimit {
                    session.upsertMessage(AgentMessage(id: "\(message)", role: .assistant,
                        text: String(repeating: "a", count: AgentSession.messageCharacterLimit)))
                }
                store.upsert(session)
            }
            let start = Date()
            store.save()
            let elapsed = Date().timeIntervalSince(start)
            store.flushPendingSave()
            let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize!
            let restored = AgentSessionStore(persistenceURL: file)
            while !restored.isLoaded { try await Task.sleep(for: .milliseconds(10)) }
            let reloaded = restored.sessions.count
            print("SESSIONS=\(count) BYTES=\(bytes) SAVE_MAIN_THREAD_MS=\(elapsed * 1000) RELOADED=\(reloaded)")
        }
    }
}
'''
        results["agent_store_exact_source"] = swift_probe("agent-store", agent_harness, (
            "DynamicIsland/managers/Agents/AgentSession.swift",
            "DynamicIsland/managers/Agents/AgentSessionStore.swift",
            "DynamicIsland/utils/PrivateContentFile.swift",
            "DynamicIsland/helpers/AppRuntimeEnvironment.swift"))
        results["combine_lifetime_control"] = swift_probe("combine-lifetime", r'''
import Combine
import Foundation
@main struct Probe {
    static func main() {
        let subject = PassthroughSubject<Int, Never>()
        var discardedCount = 0
        var retainedCount = 0
        _ = subject.sink { _ in discardedCount += 1 }
        let retained = subject.sink { _ in retainedCount += 1 }
        subject.send(1)
        withExtendedLifetime(retained) {
            print("DISCARDED_SINK_EVENTS=\(discardedCount) RETAINED_SINK_EVENTS=\(retainedCount)")
        }
    }
}
''')
        child = subprocess.Popen(
            [sys.executable, "-c", 'import sys; sys.stdout.buffer.write(b"x" * (1024 * 1024)); sys.stdout.flush()'],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        started = time.monotonic()
        try:
            try:
                child.wait(timeout=0.5)
                blocked = False
            except subprocess.TimeoutExpired:
                blocked = True
            stdout, _ = child.communicate(timeout=5)
            results["pipe_order_control"] = {
                "wait_before_drain_blocked": blocked, "drained_bytes": len(stdout),
                "exit": child.returncode, "elapsed_seconds": round(time.monotonic() - started, 3)}
        finally:
            if child.poll() is None:
                child.kill()
                child.communicate()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
    print(json.dumps(results, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    main()
