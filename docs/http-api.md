# Local HTTP API

Keycap Context listens only on `127.0.0.1`. The default port is `47821`; set
`KEYCAP_PORT` or pass `--port` to the host, and set `KEYCAP_BROKER_URL` in
adapters when using a different port.

## Authentication

Loopback binding proves only that the caller is on this machine. It does not
distinguish a trusted adapter from any other local process, nor from a web page
the user is visiting: a CORS-simple `POST` from a page reaches the broker with a
loopback `Host` header like any other client. Every request is therefore
authenticated.

On first launch the host writes a 32-byte random token, owner-readable only, to
`~/Library/Application Support/Keycap Context/token` (override with
`KEYCAP_TOKEN_PATH`). Adapters present it as `Authorization: Bearer <token>` or
`X-Keycap-Token: <token>`; the bundled adapters read the file automatically, and
`KEYCAP_TOKEN` overrides it.

This secret protects against other machine accounts and, together with the
fetch-metadata checks, browser pages. It is not a sandbox boundary against an
untrusted process already running as the same macOS user: that process can read
the same owner-readable token as an adapter.

```sh
curl -s -H "Authorization: Bearer $(cat ~/Library/Application\ Support/Keycap\ Context/token)" \
  http://127.0.0.1:47821/health
```

The broker answers `401 Unauthorized` for a missing or wrong token and `403
Forbidden` for a non-loopback `Host` header or for any request carrying browser
fetch metadata (`Origin`, or `Sec-Fetch-Site` other than `none`). Adapters treat
both as "broker unavailable" and fall back to the agent's own terminal prompt,
so a stale token degrades safely rather than blocking an agent.

## Endpoints

- `GET /health` returns broker, queue, pause, agent, and device health.
- `GET /v1/capabilities` reports API and device protocol capabilities.
- `POST /v1/requests/wait` submits an `AgentRequest` and holds the response
  until it is selected or cancelled.
- `DELETE /v1/requests/{id}` cancels one pending request.
- `POST /v1/sessions/cancel` with `{"session":"..."}` cancels all requests
  owned by a session.
- `POST /v1/sessions/status` reports `working`, `waiting`, `completed`, `failed`,
  or `idle` activity for a session.
- `GET /v1/sessions` returns the persistent four-key session assignments.
- `DELETE /v1/sessions/{session}` unassigns a session from its physical key.
- `POST /v1/sessions/control` queues `focus`, `interrupt`, `resume`, `cancel`,
  or `markRead` for a session.
- `GET /v1/sessions/{session}/commands` atomically drains pending controls for
  a persistent adapter bridge.
- `GET /v1/history` returns the bounded local approval/control audit history.

The broker rejects malformed requests with `422`, duplicate IDs with `409`,
new requests while paused with `503`, and requests beyond the 64-entry queue
limit with `429`. A disconnected waiting client is
removed from the queue automatically.

The server authenticates every request, validates the HTTP `Host` header as
loopback-only, refuses browser-originated requests, and bounds request and field
sizes before presentation.

Requests support one to sixteen choices, optional `allowsMultiple`, optional
`progress` (`current` and `total`), optional `timeoutSeconds`, and an optional
six-digit `accentColor`. Multi-select responses include ordered `choiceIds`;
single-select responses retain the backward-compatible `choiceId` field.
Requests may set `risk` to `destructive` to activate hold-to-confirm behavior.
Requests may also provide `clientApp`, a macOS bundle identifier used only to
focus the originating terminal. The host never accepts remote network clients.
