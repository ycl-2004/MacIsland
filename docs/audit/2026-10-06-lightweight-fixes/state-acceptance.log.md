```text
MET: claude-plain-tool — Optional(main.AgentEventPhase.toolStarted)
MET: codex-plain-tool — Optional(main.AgentEventPhase.toolStarted)
MET: grok-plain-tool — Optional(main.AgentEventPhase.toolStarted)
MET: claude-notification-idle_prompt — nil
MET: claude-notification-auth_success — nil
MET: claude-notification-agent_completed — nil
MET: claude-notification-elicitation_complete — nil
MET: claude-notification-unknown_future_type — nil
MET: claude-permission — Optional(main.AgentEventPhase.needsAttention)
MET: claude-tool-failure — Optional(main.AgentEventPhase.thinking)
MET: claude-turn-failure — Optional(main.AgentEventPhase.turnFailed)
MET: codex-tool-return — Optional(main.AgentEventPhase.thinking)
MET: grok-unknown-notification — nil
MET: grok-cancel — Optional(main.AgentEventPhase.turnCancelled)
MET: resume-clears-wait — thinking
MET: end-clears-wait — idle, disconnected=true
MET: late-hook — thinking
MET: duplicate-finish — finishedAt moved=false
MET: lost-live-feed — waiting=false
MET: finish-expiry — highlight expired=true
MET: wait-priority — codex:12345678-1234-4123-8123-123456789abc
MET: single-removal-publication — updates=1
MET: parallel-tool-vs-wait — needsAttention(message: Optional("Approval required"))
MET: old-turn-completion — thinking
MET: cancel-highlight — highlight=false
MET: live-turn-failure — failed(message: Optional("fixture error"))
MET: owned-approval-visible — requests=2
MET: multiple-approvals — requests=1, state=needsAttention(message: Optional("Approval required"))
MET: approval-send-guard — canSend=false
MET: approval-resolution — requests=0
MET: live-finish-dedup — deadline unchanged
MET: settled-turn-late-item — finished
MET: settled-turn-late-request — settled turn remains finished
MET: foreign-approval-observation — answerable=0
MET: owner-feed-precedence — pending wait retained
MET: uncertain-input-guard — input blocked, terminal not declared ended
MET: hook-parallel-requests — requests=2
MET: hook-matching-resolution — one question remains
MET: hook-all-resolved — thinking
MET: hook-old-turn-id — current turn=b
MET: hook-cancel-then-idle — cancelled without success flash
MET: hook-overflow-uncertainty — uncertain=true
MET: legacy-hook-profile — profiles are separate
MET: attention-settling-window — immediate guard, delayed reminder
MET: owner-emission-order — older status rejected
MET: subscribe-approval-race — foreign approval retained during subscription
MET: ownership-is-turn-specific — foreign next turn remains read-only
MET: approval-generation-guard — current requests=1, stale replies=0
MET: stale-hook-delivery-guard — current route retained
MET: stale-park-guard — old hook released, current route retained
MET: legacy-session-decode — legacy snapshot retained
Policy met: 51/51; gaps: 0

```
