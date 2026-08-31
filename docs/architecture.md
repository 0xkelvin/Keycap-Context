# Architecture

The product separates agent integrations, request policy, presentation, and
hardware. No adapter is allowed to write a number into whichever application
happens to have focus.

```text
Claude / Codex / generic CLI
            |
       agent adapter
            |
       local HTTP API
            |
     request broker/queue
       |            |
 macOS overlay   serial device
                     |
              XIAO nRF54L15
                     |
               NeoKey 1x4
```

## Request model

An adapter submits a request containing source/session metadata, the complete
question text, and one to four ordered choices. Labels and descriptions are
displayed verbatim. The broker never inserts a synthetic `Details` choice.

Only the first request is active. Later requests remain FIFO-queued. Resolving
the active request atomically removes it, replies to its adapter, and presents
the next request.

Dismissal follows the same lifecycle as a response but carries a cancellation
instead of a selected choice. The overlay's agent-specific **Handle in…** button
and its temporary Escape shortcut both cancel only the active request. Holding
Escape cannot drain the queue; the shortcut rearms after key release.

## Trust boundaries

- The HTTP listener binds only to `127.0.0.1`.
- Device input is semantic (`BUTTON 1 DOWN`), not USB HID keyboard input.
- A response is routed by request ID and cannot land in the focused editor.
- Accessibility permission is not required by the primary design.
- Escape is registered only while an overlay is visible and does not use a
  global event tap.
- Adapter content is untrusted display text and never interpreted as markup.

## Adapter levels

1. Native structured protocol: preferred for Codex App Server and agent SDKs.
2. Lifecycle hook: used by the initial Claude Code adapter.
3. Managed PTY parser: future compatibility fallback for other CLIs.

The hardware and broker API remain stable when adapters change.
