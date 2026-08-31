# Claude Code adapter

The adapter uses two documented Claude Code lifecycle hooks:

- `PermissionRequest` for allow/always-allow/deny decisions
- `PreToolUse` filtered to `AskUserQuestion` for exact multiple-choice input
- `PreToolUse` filtered to `ExitPlanMode` for plan approval

The hook posts to the local broker and blocks until a physical or overlay
selection resolves the request. If the broker cannot be reached, it emits no
decision and Claude retains its normal terminal interaction.

Choose **Handle in Claude** in the overlay or press Escape to dismiss the active
request without making a selection. The broker releases the waiting hook, which
emits no decision so Claude presents its normal terminal interaction.

`AskUserQuestion` is excluded from the generic `PermissionRequest` bridge. This
prevents Claude's raw question payload from being queued as a second permission
overlay after a question is handed back to the terminal.

## Configure

1. Start `keycap-host`.
2. Copy the entries in `settings.fragment.json` into the existing `hooks`
   object in `~/.claude/settings.json`.
3. Replace `/ABSOLUTE/PATH/TO` with this repository's absolute path.
4. Run `/hooks` in Claude Code and verify both entries.

Do not replace an existing `hooks` object wholesale. Merge the two event arrays
with any hooks already configured.

Single-choice, multi-select, and batches of several questions are supported.
Multi-select uses an explicit Submit button in the overlay; protocol-v2 hardware
uses a long press on key 4 to submit.

## How an answered question is returned

The hook allows the call with the answers filled into `updatedInput`.
`AskUserQuestion` honours a pre-filled `answers` field and returns it without
prompting, so the question is not asked again in the terminal.

Handing the overlay back instead returns nothing at all, which lets Claude Code
prompt in the terminal as usual.

Denying the call and carrying the answers in `permissionDecisionReason` also
works, but Claude Code renders a blocked call as an error, which reads like a
failure. Measured against a live broker, the allowed call returns in the same
second the keypad resolves the overlay; a terminal prompt instead shows up as a
gap of tens of seconds.
