# Agent Console

Agent Console assigns up to four recent agent sessions to the four physical
keys. Waiting sessions are protected from replacement; when all slots are full,
the oldest idle or completed session is replaced first.

## States

Settings defaults to the selected four-key standby lighting effect. Enable
**Show agent activity instead of the standby effect** to display these states
on protocol-v3 hardware while no approval overlay is visible.

| State | LED | Meaning |
| --- | --- | --- |
| Working | Pulsing blue | Agent is reasoning or executing tools |
| Waiting | Pulsing orange | Agent needs a decision |
| Destructive | Pulsing pink | Decision can modify or remove data |
| Completed | Green | Completed activity has not been acknowledged |
| Failed | Pulsing red | Agent or tool failed |
| Idle | Dim blue | Session is assigned but inactive |

The menu-bar **Agent Console…** window shows source, project, current state,
focus/interrupt/resume/cancel controls, and the last 500 local status, approval,
resolution, and control events. The history contains summaries—not secrets or
complete terminal transcripts—and is stored in Application Support.

Persistent adapters drain control commands from the local HTTP API. The Codex
App Server bridge maps interrupt/cancel to its native `turn/interrupt` request.
Hook-only adapters receive the status and approval features but cannot interrupt
a tool that is already running; the command remains available to a future
persistent bridge.

## Context profiles

When a key has no assigned agent, a short press may execute the first profile
matching the frontmost application's bundle identifier and project rule.
Actions can focus or interrupt an agent, open an HTTP(S) URL, or run a local
shell command. Interrupts and shell commands always require confirmation.
Settings renders the four actions before assignment so workflows can be
reviewed without executing them.
