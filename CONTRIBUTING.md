# Contributing to Keycap Context

Thank you for improving Keycap Context. Keep changes focused, include tests for
new protocol or broker behavior, and preserve compatibility with protocol v1.

## Development checks

```sh
cd host/macos && swift test
python3 -m unittest discover -s adapters/shared/tests -v
python3 -m unittest discover -s adapters/claude/tests -v
python3 -m unittest discover -s adapters/codex/tests -v
python3 -m unittest discover -s adapters/gemini/tests -v
python3 -m unittest discover -s adapters/antigravity/tests -v
west twister -T firmware/tests -p native_sim --inline-logs
```

Use SPDX headers on source files. Public protocol changes require corresponding
updates to `docs/protocol.md`, tests, and a compatibility note in `CHANGELOG.md`.

## Pull requests

Explain the user-visible outcome, how it was tested, and whether host, adapter,
or firmware upgrades are required. Do not include credentials, session data, or
captured agent prompts in fixtures or logs.
