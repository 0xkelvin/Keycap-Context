# Antigravity adapter

The Antigravity plugin routes `PreToolUse` approvals to Keycap Context and
reports invocation, tool, completion, and failure states to the four-agent
console. Escape or **Handle in Antigravity** returns `decision: ask`, preserving
Antigravity's native permission UI.

`ask_question` deliberately remains native because Antigravity's `PreToolUse`
contract can gate the tool but cannot inject the selected answers.

Install the plugin with:

```sh
agy plugin install "/path/to/adapters/antigravity/plugin"
```

The main installer substitutes the absolute hook path before staging it.
