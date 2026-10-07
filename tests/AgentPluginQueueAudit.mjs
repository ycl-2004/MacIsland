import { readFileSync } from "node:fs";
import { EventEmitter } from "node:events";
import assert from "node:assert/strict";

// Exact production preamble, with only child creation/timing replaced. No CLI,
// user config, transcript, clipboard or real child is accessed.
const source = readFileSync("DynamicIsland/managers/Agents/AgentPluginFile.swift", "utf8");
const marker = 'return #"""';
assert(source.includes(marker));
const preamble = source.split(marker)[1].split('"""#')[0]
  .replace('import { spawn } from "node:child_process";', "")
  .replace('\\#(literal(scriptPath))', '"/fake/atoll-hook"')
  .replace('\\#(literal(sourceID))', '"fixture"');

async function replay(body, stalled = false, stdinError = false) {
  const forwarded = [];
  let kills = 0, active = 0, peakChildren = 0;
  function fakeSpawn(_executable, args) {
    const record = { event: args[2] };
    forwarded.push(record);
    const child = new EventEmitter();
    child.stdin = new EventEmitter();
    active += 1;
    peakChildren = Math.max(peakChildren, active);
    let closed = false;
    const close = () => { if (!closed) { closed = true; active -= 1; child.emit("close", 0); } };
    child.kill = () => { kills += 1; close(); };
    child.stdin.end = (json) => {
      record.payload = JSON.parse(json);
      if (stdinError) setTimeout(() => child.stdin.emit("error", new Error("fixture broken pipe")), 1);
      else if (!stalled) setTimeout(close, 1);
    };
    return child;
  }
  const clock = (callback, ms) => setTimeout(callback, ms === 2000 ? 5 : ms);
  const execute = new Function("spawn", "setTimeout", `${preamble}
    ${body}
    const queued = atollEvents.length, uncertain = atollUncertain.size;
    return atollFlush(1500).then(() => ({queued, uncertain}));
  `);
  const counts = await execute(fakeSpawn, clock);
  return { forwarded, kills, peakChildren, active, ...counts };
}

const results = [];
const gap = await replay(`
  const originalSend = atollSend;
  let inject = true;
  atollSend = (event, payload) => {
    const sent = originalSend(event, payload);
    if (inject) {
      inject = false;
      sent.then(() => queueMicrotask(() => atollReport("session.deleted", {session_id: "fixture"})));
    }
    return sent;
  };
  atollReport("tool.running", {session_id: "fixture"});
`);
assert(gap.forwarded.some(x => x.event === "session.deleted"), "An event queued between drain completion and finally must restart draining.");
results.push({fixture: "event-during-drain-settlement", passed: true, forwarded: gap.forwarded.length});
const capacity = await replay(`
  for (let i = 0; i < 32; i++) atollReport("tool.running", {session_id: "fixture", i});
  atollReport("session.deleted", {session_id: "fixture"});
`);
assert(capacity.forwarded.some(x => x.event === "session.deleted"));
assert.equal(capacity.peakChildren, 1);
results.push({fixture: "critical-terminal-event-at-capacity", passed: true, forwarded: capacity.forwarded.length});

const burst = await replay(`
  for (let i = 0; i < 10000; i++) atollReport("tool.running", {session_id: "fixture", i});
  atollReport("permission.asked", {session_id: "fixture", request_id: "p1"});
  atollReport("permission.asked", {session_id: "fixture", request_id: "p2"});
  atollReport("permission.replied", {session_id: "fixture", request_id: "p1"});
  atollReport("session.deleted", {session_id: "fixture"});
`);
assert(burst.queued <= 64 && burst.uncertain <= 64);
assert.deepEqual(burst.forwarded.filter(x => x.event.startsWith("permission")).map(x => x.payload.request_id), ["p1", "p2", "p1"]);
assert(burst.forwarded.some(x => x.payload.i === 9999));
assert(burst.forwarded.some(x => x.event === "session.deleted"));
results.push({fixture: "bounded-coalescing-and-critical-order", passed: true, queued: burst.queued});

const overload = await replay(`
  for (let i = 0; i < 200; i++) atollReport("permission.asked", {session_id: "fixture", request_id: String(i)});
`);
assert(overload.queued <= 64 && overload.uncertain <= 64);
assert.equal(overload.forwarded.at(-1).event, "atoll.transport.uncertain");
results.push({fixture: "critical-overflow-exposes-uncertainty", passed: true, queued: overload.queued});

const deadline = await replay(`atollReport("tool.running", {session_id: "fixture"});`, true);
assert(deadline.kills >= 1 && deadline.peakChildren === 1 && deadline.active === 0);
assert(deadline.forwarded.some(x => x.event === "atoll.transport.uncertain"));
results.push({fixture: "stalled-owned-child-is-killed", passed: true, kills: deadline.kills});
const brokenPipe = await replay(`atollReport("tool.running", {session_id: "fixture"}); atollReport("session.deleted", {session_id: "fixture"});`, false, true);
assert(brokenPipe.kills >= 2 && brokenPipe.peakChildren === 1 && brokenPipe.active === 0);
assert(brokenPipe.forwarded.some(x => x.event === "atoll.transport.uncertain"));
results.push({fixture: "broken-pipe-retains-child-ownership-until-close", passed: true, kills: brokenPipe.kills});
const large = await replay(`atollReport("chat.message", {session_id: "fixture", prompt: "x".repeat(5 * 1024 * 1024), tool_input: {command: "y".repeat(1024 * 1024)}});`);
assert.equal(large.forwarded[0].payload.prompt.length, 16384);
assert.equal(large.forwarded[0].payload.tool_input.command.length, 1024);
results.push({fixture: "bounded-detached-payload", passed: true});
console.log(JSON.stringify({results, real_children_spawned: 0}, null, 2));
