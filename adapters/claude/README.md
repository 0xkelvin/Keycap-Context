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

## Why answered questions are denied, not allowed

A `PreToolUse` hook cannot hand Claude Code a tool result. `permissionDecision:
"allow"` runs the tool whatever `updatedInput` says, so answering on the keypad
and allowing the call made `AskUserQuestion` ask the same question again in the
terminal and throw the keypad answer away. `deny` is the only decision that
stops execution, and `permissionDecisionReason` is the only field that carries
text back, so the answers travel there.

Handing the overlay back still returns nothing at all, which lets Claude Code
prompt in the terminal as usual.
