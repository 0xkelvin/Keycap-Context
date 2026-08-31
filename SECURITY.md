# Security policy

Please report vulnerabilities privately to the maintainer rather than opening a
public issue. Include affected versions, reproduction steps, and potential
impact. Do not include real agent prompts, tokens, or credentials.

The broker binds only to `127.0.0.1`. Adapters must treat broker output as data,
must not execute it, and must fall back to the agent's native terminal when the
broker is unavailable. Release artifacts should be signed and checksummed.

Every broker request requires the per-install owner-readable token and requests
carrying browser fetch metadata are rejected. This protects against other local
accounts and browser pages, but not against an untrusted process already running
as the same macOS user, which can read that user's token file. Do not use the
approval surface as a security boundary between processes in one user account.
